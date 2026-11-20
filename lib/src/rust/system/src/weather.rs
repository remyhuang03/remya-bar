mod provider;

use crate::api::{WeatherLocation, WeatherResult, WeatherSnapshot, WeatherStatus};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs::{DirBuilder, File};
use std::io::{Read, Write};
use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

const FRESH_SECONDS: i64 = 15 * 60;
const STALE_SECONDS: i64 = 24 * 60 * 60;
const RETRY_DELAY: Duration = Duration::from_secs(30);
const CACHE_LIMIT: u64 = 128 * 1024;

#[derive(Clone, Copy, PartialEq, Serialize, Deserialize)]
struct Point {
    latitude: i32,
    longitude: i32,
}

impl Point {
    fn new(latitude: f64, longitude: f64) -> Self {
        // Integer millionths survive a cache round trip without float drift.
        Self {
            latitude: (latitude * 1_000_000.0).round() as i32,
            longitude: (longitude * 1_000_000.0).round() as i32,
        }
    }
}

#[derive(Serialize, Deserialize)]
struct CacheEntry {
    point: Point,
    snapshot: WeatherSnapshot,
}

#[derive(Default)]
struct WeatherCache {
    loaded: bool,
    entry: Option<CacheEntry>,
    attempt: Option<(Point, Instant, Option<String>)>,
}

impl WeatherCache {
    fn result(&self, point: Point, now: i64, error: Option<String>) -> WeatherResult {
        let snapshot = self.entry.as_ref().and_then(|entry| {
            let age = now.saturating_sub(entry.snapshot.fetched_at);
            (entry.point == point && (0..STALE_SECONDS).contains(&age))
                .then_some((age, &entry.snapshot))
        });
        let status = match snapshot {
            Some((age, _)) if age < FRESH_SECONDS && error.is_none() => WeatherStatus::Fresh,
            Some(_) => WeatherStatus::Stale,
            None => WeatherStatus::Unavailable,
        };
        WeatherResult {
            status,
            snapshot: snapshot.map(|(_, snapshot)| snapshot.clone()),
            error,
        }
    }
}

static CACHE: Mutex<WeatherCache> = Mutex::const_new(WeatherCache {
    loaded: false,
    entry: None,
    attempt: None,
});

pub(crate) async fn search(query: &str, language: &str) -> Result<Vec<WeatherLocation>, String> {
    let query = query.trim();
    if query.len() > 256 || query.chars().any(char::is_control) {
        return Err("Invalid weather location search".into());
    }
    let language = if language.is_empty() { "en" } else { language };
    if !(language.len() == 2 && language.bytes().all(|byte| byte.is_ascii_lowercase())) {
        return Err("Expected a two-letter weather search language".into());
    }
    if query.chars().take(2).count() < 2 {
        return Ok(Vec::new());
    }
    provider::search(query, language).await
}

pub(crate) async fn refresh(
    latitude: f64,
    longitude: f64,
    force: bool,
) -> Result<WeatherResult, String> {
    if !(-90.0..=90.0).contains(&latitude) || !(-180.0..=180.0).contains(&longitude) {
        return Err("Invalid weather coordinates".into());
    }
    let point = Point::new(latitude, longitude);
    let mut cache = CACHE.lock().await;
    if !cache.loaded {
        cache.entry = tokio::task::spawn_blocking(|| read_cache(&cache_path()?))
            .await
            .ok()
            .flatten();
        cache.loaded = true;
    }

    let now = Utc::now().timestamp();
    if let Some((previous, time, error)) = &cache.attempt
        && *previous == point
        && time.elapsed() < RETRY_DELAY
    {
        return Ok(cache.result(point, now, error.clone()));
    }

    let cached = cache.result(point, now, None);
    let last_failed = matches!(&cache.attempt, Some((previous, _, Some(_))) if *previous == point);
    if !force && !last_failed && cached.status == WeatherStatus::Fresh {
        return Ok(cached);
    }

    let error = match provider::forecast(latitude, longitude).await {
        Ok(snapshot) => {
            let entry = CacheEntry { point, snapshot };
            let encoded = serde_json::to_vec(&entry).ok();
            cache.entry = Some(entry);
            if let Some(encoded) = encoded
                && let Some(path) = cache_path()
            {
                // A cache write failure cannot invalidate a live result.
                let _ = tokio::task::spawn_blocking(move || write_cache(&path, &encoded)).await;
            }
            None
        }
        Err(error) => Some(error),
    };
    cache.attempt = Some((point, Instant::now(), error.clone()));
    Ok(cache.result(point, Utc::now().timestamp(), error))
}

fn cache_path() -> Option<PathBuf> {
    let absolute = |name| {
        std::env::var_os(name)
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
    };
    Some(
        absolute("XDG_CACHE_HOME")
            .or_else(|| absolute("HOME").map(|home| home.join(".cache")))?
            .join("remya/bar/weather.json"),
    )
}

fn read_cache(path: &Path) -> Option<CacheEntry> {
    let mut encoded = Vec::new();
    File::open(path)
        .ok()?
        .take(CACHE_LIMIT + 1)
        .read_to_end(&mut encoded)
        .ok()?;
    if encoded.len() as u64 > CACHE_LIMIT {
        return None;
    }
    serde_json::from_slice(&encoded).ok()
}

fn write_cache(path: &Path, encoded: &[u8]) -> std::io::Result<()> {
    let directory = path.parent().expect("weather cache has a parent");
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(directory)?;
    let mut file = tempfile::NamedTempFile::new_in(directory)?;
    file.write_all(encoded)?;
    file.as_file().sync_all()?;
    file.persist(path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn saved_weather_is_location_scoped_and_expires() {
        let point = Point::new(25.0, 121.5);
        let entry = CacheEntry {
            point,
            snapshot: WeatherSnapshot {
                fetched_at: 100,
                timezone: "Asia/Taipei".into(),
                current: None,
                hourly: vec![],
                daily: vec![crate::api::WeatherDay {
                    date: "2026-11-20".into(),
                    low_c: Some(16.0),
                    high_c: Some(25.0),
                    condition: None,
                    precipitation_probability: None,
                }],
            },
        };
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("bar/weather.json");
        write_cache(&path, &serde_json::to_vec(&entry).unwrap()).unwrap();
        let cache = WeatherCache {
            entry: read_cache(&path),
            ..Default::default()
        };
        assert_eq!(cache.result(point, 100, None).status, WeatherStatus::Fresh);
        assert_eq!(
            cache.result(point, 101, Some("offline".into())).status,
            WeatherStatus::Stale
        );
        assert_eq!(
            cache.result(point, 100 + FRESH_SECONDS, None).status,
            WeatherStatus::Stale
        );
        assert!(
            cache
                .result(point, 100 + STALE_SECONDS, None)
                .snapshot
                .is_none()
        );
        assert!(cache.result(point, 99, None).snapshot.is_none());
        assert!(
            cache
                .result(Point::new(26.0, 121.5), 100, None)
                .snapshot
                .is_none()
        );
    }

    #[test]
    fn rejects_invalid_coordinates_without_a_request() {
        tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap()
            .block_on(async {
                assert!(refresh(f64::NAN, 0.0, false).await.is_err());
                assert!(refresh(0.0, 180.1, false).await.is_err());
                assert!(search("x", "en").await.unwrap().is_empty());
            });
    }
}
