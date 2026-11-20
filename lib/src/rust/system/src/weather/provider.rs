use std::sync::LazyLock;
use std::time::Duration;

use chrono::{DateTime, FixedOffset, Utc};
use reqwest::{Client, redirect::Policy};
use serde::Deserialize;
use serde_json::Value;

use crate::api::{
    WeatherCondition, WeatherCurrent, WeatherDay, WeatherHour, WeatherLocation, WeatherSnapshot,
};

const GEOCODING_URL: &str = "https://geocoding-api.open-meteo.com/v1/search";
const FORECAST_URL: &str = "https://api.open-meteo.com/v1/forecast";
const MAX_RESPONSE_BYTES: usize = 256 * 1024;
const INVALID_RESPONSE: &str = "Invalid weather provider response";

static CLIENT: LazyLock<Result<Client, reqwest::Error>> = LazyLock::new(|| {
    Client::builder()
        .https_only(true)
        .redirect(Policy::none())
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(15))
        .user_agent(concat!("Remya-Bar/", env!("CARGO_PKG_VERSION")))
        .build()
});

pub(super) async fn search(query: &str, language: &str) -> Result<Vec<WeatherLocation>, String> {
    let data = get(
        GEOCODING_URL,
        &[("name", query), ("language", language), ("count", "10")],
    )
    .await?;
    parse_locations(data)
}

pub(super) async fn forecast(latitude: f64, longitude: f64) -> Result<WeatherSnapshot, String> {
    let data = get(
        FORECAST_URL,
        &[
            ("latitude", &latitude.to_string()),
            ("longitude", &longitude.to_string()),
            ("timezone", "auto"),
            ("timeformat", "unixtime"),
            ("temperature_unit", "celsius"),
            ("wind_speed_unit", "kmh"),
            ("forecast_hours", "25"),
            ("forecast_days", "7"),
            (
                "current",
                "temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m",
            ),
            ("hourly", "temperature_2m,weather_code,is_day,precipitation_probability"),
            ("daily", "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
        ],
    )
    .await?;
    parse_forecast(data, Utc::now().timestamp())
}

async fn get(url: &str, query: &[(&str, &str)]) -> Result<Value, String> {
    let client = CLIENT
        .as_ref()
        .map_err(|_| "Could not initialize the weather client")?;
    let mut response = client.get(url).query(query).send().await.map_err(|error| {
        if error.is_timeout() {
            "Weather request timed out"
        } else {
            "Could not reach the weather provider"
        }
    })?;
    let status = response.status();
    if !status.is_success() {
        return Err(format!(
            "Weather provider returned HTTP {}",
            status.as_u16()
        ));
    }
    let length = response.content_length().unwrap_or_default();
    if length > MAX_RESPONSE_BYTES as u64 {
        return Err("Weather provider response is too large".into());
    }
    let mut body = Vec::with_capacity(length as usize);
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|_| "Could not read weather response")?
    {
        if chunk.len() > MAX_RESPONSE_BYTES - body.len() {
            return Err("Weather provider response is too large".into());
        }
        body.extend_from_slice(&chunk);
    }
    let data: Value = serde_json::from_slice(&body).map_err(|_| INVALID_RESPONSE)?;
    if !data.is_object() || data.get("error").and_then(Value::as_bool) == Some(true) {
        return Err(INVALID_RESPONSE.into());
    }
    Ok(data)
}

#[derive(Deserialize)]
struct Place {
    id: i32,
    name: String,
    admin1: Option<String>,
    country: Option<String>,
    latitude: f64,
    longitude: f64,
}

fn parse_locations(mut data: Value) -> Result<Vec<WeatherLocation>, String> {
    let Some(results) = data
        .as_object_mut()
        .and_then(|object| object.remove("results"))
    else {
        return Ok(Vec::new());
    };
    let results: Vec<Value> = serde_json::from_value(results).map_err(|_| INVALID_RESPONSE)?;
    Ok(results
        .into_iter()
        .filter_map(|result| serde_json::from_value::<Place>(result).ok())
        .filter(|place| {
            place.id > 0
                && valid_label(&place.name)
                && (-90.0..=90.0).contains(&place.latitude)
                && (-180.0..=180.0).contains(&place.longitude)
        })
        .map(|place| WeatherLocation {
            id: Some(place.id),
            name: place.name,
            region: place.admin1.filter(|value| valid_label(value)),
            country: place.country.filter(|value| valid_label(value)),
            latitude: place.latitude,
            longitude: place.longitude,
        })
        .take(10)
        .collect())
}

fn valid_label(value: &str) -> bool {
    !value.trim().is_empty() && value.len() <= 256 && !value.chars().any(char::is_control)
}

#[derive(Deserialize)]
struct Current {
    time: i64,
    temperature_2m: Option<f64>,
    apparent_temperature: Option<f64>,
    weather_code: Option<u8>,
    is_day: Option<u8>,
    relative_humidity_2m: Option<f64>,
    wind_speed_10m: Option<f64>,
}

#[derive(Deserialize)]
struct Hourly {
    time: Vec<Option<i64>>,
    temperature_2m: Option<Vec<Option<f64>>>,
    weather_code: Option<Vec<Option<u8>>>,
    is_day: Option<Vec<Option<u8>>>,
    precipitation_probability: Option<Vec<Option<f64>>>,
}

#[derive(Deserialize)]
struct Daily {
    time: Vec<Option<i64>>,
    temperature_2m_min: Option<Vec<Option<f64>>>,
    temperature_2m_max: Option<Vec<Option<f64>>>,
    weather_code: Option<Vec<Option<u8>>>,
    precipitation_probability_max: Option<Vec<Option<f64>>>,
}

fn parse_forecast(mut data: Value, fetched_at: i64) -> Result<WeatherSnapshot, String> {
    let timezone = data
        .get("timezone")
        .and_then(Value::as_str)
        .filter(|zone| !zone.trim().is_empty())
        .ok_or(INVALID_RESPONSE)?
        .to_owned();
    let offset = data
        .get("utc_offset_seconds")
        .and_then(Value::as_i64)
        .and_then(|offset| i32::try_from(offset).ok())
        .and_then(FixedOffset::east_opt);

    let mut hourly = serde_json::from_value::<Hourly>(data["hourly"].take())
        .map(parse_hours)
        .unwrap_or_default();
    let current = serde_json::from_value::<Current>(data["current"].take())
        .ok()
        .and_then(|current| parse_current(current, &hourly));
    let cutoff = current
        .as_ref()
        .map_or(fetched_at, |current| current.valid_at);
    hourly.retain(|hour| hour.valid_at > cutoff);
    hourly.truncate(25);
    let mut daily = offset
        .zip(serde_json::from_value::<Daily>(data["daily"].take()).ok())
        .map(|(offset, daily)| parse_days(daily, offset))
        .unwrap_or_default();
    daily.truncate(7);

    if current.is_none() && hourly.is_empty() && daily.is_empty() {
        return Err("Weather provider returned no usable forecast data".into());
    }
    Ok(WeatherSnapshot {
        fetched_at,
        timezone,
        current,
        hourly,
        daily,
    })
}

fn parse_current(raw: Current, hourly: &[WeatherHour]) -> Option<WeatherCurrent> {
    DateTime::from_timestamp(raw.time, 0)?;
    // Open-Meteo reports precipitation probability for the preceding hour.
    let precipitation_probability = hourly
        .iter()
        .find(|hour| (0..=3600).contains(&(hour.valid_at - raw.time)))
        .and_then(|hour| hour.precipitation_probability);
    let current = WeatherCurrent {
        valid_at: raw.time,
        temperature_c: raw.temperature_2m,
        feels_like_c: raw.apparent_temperature,
        condition: condition(raw.weather_code, raw.is_day),
        humidity_percent: percent(raw.relative_humidity_2m),
        wind_kmh: raw.wind_speed_10m.filter(|wind| *wind >= 0.0),
        precipitation_probability,
    };
    (current.temperature_c.is_some()
        || current.feels_like_c.is_some()
        || current.condition.is_some()
        || current.humidity_percent.is_some()
        || current.wind_kmh.is_some()
        || current.precipitation_probability.is_some())
    .then_some(current)
}

fn parse_hours(raw: Hourly) -> Vec<WeatherHour> {
    let len = raw.time.len();
    let mut hourly: Vec<_> = raw
        .time
        .iter()
        .enumerate()
        .filter_map(|(index, &time)| {
            let valid_at = time?;
            DateTime::from_timestamp(valid_at, 0)?;
            let hour = WeatherHour {
                valid_at,
                temperature_c: at(&raw.temperature_2m, index, len),
                condition: condition(
                    at(&raw.weather_code, index, len),
                    at(&raw.is_day, index, len),
                ),
                precipitation_probability: percent(at(&raw.precipitation_probability, index, len)),
            };
            (hour.temperature_c.is_some()
                || hour.condition.is_some()
                || hour.precipitation_probability.is_some())
            .then_some(hour)
        })
        .collect();
    hourly.sort_by_key(|hour| hour.valid_at);
    hourly.dedup_by_key(|hour| hour.valid_at);
    hourly
}

fn parse_days(raw: Daily, offset: FixedOffset) -> Vec<WeatherDay> {
    let len = raw.time.len();
    let mut daily: Vec<_> = raw
        .time
        .iter()
        .enumerate()
        .filter_map(|(index, &time)| {
            // Daily buckets use the fixed response offset, including across DST changes.
            let local = time?.checked_add(i64::from(offset.local_minus_utc()))?;
            let date = DateTime::from_timestamp(local, 0)?.date_naive().to_string();
            let day = WeatherDay {
                date,
                low_c: at(&raw.temperature_2m_min, index, len),
                high_c: at(&raw.temperature_2m_max, index, len),
                condition: condition(at(&raw.weather_code, index, len), None),
                precipitation_probability: percent(at(
                    &raw.precipitation_probability_max,
                    index,
                    len,
                )),
            };
            (day.low_c.is_some()
                || day.high_c.is_some()
                || day.condition.is_some()
                || day.precipitation_probability.is_some())
            .then_some(day)
        })
        .collect();
    daily.sort_by(|a, b| a.date.cmp(&b.date));
    daily.dedup_by(|a, b| a.date == b.date);
    daily
}

fn at<T: Copy>(column: &Option<Vec<Option<T>>>, index: usize, len: usize) -> Option<T> {
    column.as_ref().filter(|column| column.len() == len)?[index]
}

fn percent(value: Option<f64>) -> Option<f64> {
    value.filter(|value| (0.0..=100.0).contains(value))
}

fn condition(code: Option<u8>, is_day: Option<u8>) -> Option<WeatherCondition> {
    use WeatherCondition::*;

    let night = is_day == Some(0);
    match code? {
        0 | 1 if night => Some(ClearNight),
        0 | 1 => Some(Clear),
        2 if night => Some(PartlyCloudyNight),
        2 => Some(PartlyCloudy),
        3 => Some(Cloudy),
        45 | 48 => Some(Fog),
        51 | 53 | 55 | 56 | 57 | 61 | 63 | 65 | 66 | 67 | 80 | 81 | 82 => Some(Rain),
        71 | 73 | 75 | 77 | 85 | 86 => Some(Snow),
        95..=97 | 99 => Some(Storm),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_locations_and_discards_invalid_matches() {
        let locations = parse_locations(json!({"results": [
            {"id": 1668341, "name": "台北市", "latitude": 25.053, "longitude": 121.526, "country": "台湾"},
            {"id": 1, "name": "Invalid", "latitude": 91, "longitude": 121},
            {"id": 2, "name": null, "latitude": 25, "longitude": 121}
        ]}))
        .unwrap();
        assert_eq!(locations.len(), 1);
        assert_eq!(locations[0].name, "台北市");
        assert!(locations[0].region.is_none());
        assert!(
            parse_locations(json!({"generationtime_ms": 0.2}))
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn parses_nullable_forecast_and_uses_local_calendar_date() {
        let data = json!({
            "timezone": "Asia/Taipei",
            "utc_offset_seconds": 28_800,
            "current": {"time": 1_795_172_400, "temperature_2m": 12.2, "weather_code": 2, "is_day": 0},
            "hourly": {
                "time": [1_795_172_400, 1_795_176_000],
                "temperature_2m": [10],
                "weather_code": [null, 97],
                "precipitation_probability": [30, 80]
            },
            "daily": {
                "time": [1_795_104_000],
                "temperature_2m_min": [null],
                "temperature_2m_max": [16],
                "weather_code": [3]
            }
        });
        let snapshot = parse_forecast(data, 1_795_172_420).unwrap();
        let current = snapshot.current.unwrap();
        assert!(matches!(
            current.condition,
            Some(WeatherCondition::PartlyCloudyNight)
        ));
        assert_eq!(current.precipitation_probability, Some(30.0));
        assert!(current.humidity_percent.is_none());
        assert_eq!(snapshot.hourly.len(), 1);
        assert!(snapshot.hourly[0].temperature_c.is_none());
        assert!(matches!(
            snapshot.hourly[0].condition,
            Some(WeatherCondition::Storm)
        ));
        assert_eq!(snapshot.daily[0].date, "2026-11-20");
        assert!(snapshot.daily[0].low_c.is_none());
    }

    #[test]
    fn preserves_other_sections_and_rejects_an_empty_forecast() {
        let mut data = json!({
            "timezone": "GMT",
            "utc_offset_seconds": 0,
            "current": {"time": null, "temperature_2m": 20},
            "hourly": {"time": [3600], "temperature_2m": [20]},
            "daily": null
        });
        let snapshot = parse_forecast(data.clone(), 0).unwrap();
        assert!(snapshot.current.is_none());
        assert_eq!(snapshot.hourly[0].temperature_c, Some(20.0));
        assert!(snapshot.daily.is_empty());
        data["hourly"]["temperature_2m"] = json!([null]);
        assert!(parse_forecast(data, 0).is_err());
    }
}
