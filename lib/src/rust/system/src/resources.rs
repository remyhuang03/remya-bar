use crate::api::{ResourceDetails, SystemSnapshot};
use crate::metrics::NetworkSnapshot;
use crate::metrics::read_number;
use chrono::{Datelike, NaiveDateTime, Timelike};
use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

const BARS: usize = 18;
const MAX_WINDOW: Duration = Duration::from_secs(600);
const SENSOR_DISCOVERY: Duration = Duration::from_secs(60);

#[derive(Default)]
pub(crate) struct History {
    points: VecDeque<Point>,
    gpu_id: Option<String>,
}

struct Point {
    time: Instant,
    gpu_id: Option<String>,
    values: [Option<f64>; 4],
}

impl History {
    pub(crate) fn record(
        &mut self,
        time: Instant,
        window: Duration,
        refresh_interval: Duration,
        snapshot: &mut SystemSnapshot,
        gpu_measured: bool,
    ) {
        let Some(details) = snapshot.resources.as_mut() else {
            return;
        };
        let gpus = &snapshot.gpus;
        let gpu = gpus
            .iter()
            .find(|gpu| Some(&gpu.id) == self.gpu_id.as_ref())
            .filter(|gpu| gpu.utilization_percent.is_some())
            .or_else(|| gpus.iter().find(|gpu| gpu.utilization_percent.is_some()))
            .or_else(|| {
                gpus.iter()
                    .find(|gpu| Some(&gpu.id) == self.gpu_id.as_ref())
            })
            .or_else(|| gpus.first());
        if gpu_measured {
            self.gpu_id = gpu.map(|gpu| gpu.id.clone());
        }
        details.gpu_id = self.gpu_id.clone();
        let network = snapshot.network_overview.as_ref();
        self.points.push_back(Point {
            time,
            gpu_id: self.gpu_id.clone(),
            values: [
                snapshot.cpu_percent,
                gpu.filter(|_| gpu_measured)
                    .and_then(|gpu| gpu.utilization_percent),
                network.and_then(|network| network.download_bytes_per_second),
                network.and_then(|network| network.upload_bytes_per_second),
            ],
        });
        while self
            .points
            .front()
            .is_some_and(|point| time.duration_since(point.time) >= MAX_WINDOW)
        {
            self.points.pop_front();
        }
        self.populate(time, window, refresh_interval, details);
    }

    fn populate(
        &self,
        time: Instant,
        window: Duration,
        refresh_interval: Duration,
        details: &mut ResourceDetails,
    ) {
        let window_ms = window.as_millis().max(1);
        let refresh_ms = refresh_interval.as_millis().max(1);
        let bars = (window_ms / refresh_ms).clamp(1, BARS as u128) as usize;
        let mut bins: [Vec<(f64, u32)>; 4] = std::array::from_fn(|_| vec![(0.0, 0u32); bars]);
        for point in &self.points {
            let Some(age) = time.checked_duration_since(point.time) else {
                continue;
            };
            if age >= window {
                continue;
            }
            let raw = (age.as_millis() * bars as u128 / window_ms) as usize;
            let index = bars - 1 - raw.min(bars - 1);
            for (metric, value) in point.values.iter().enumerate() {
                if let Some(value) = value
                    && (metric != 1 || point.gpu_id == self.gpu_id)
                {
                    let (sum, count) = &mut bins[metric][index];
                    *sum += value;
                    *count += 1;
                }
            }
        }
        let [cpu, gpu, down, up] = bins.map(|bins| {
            bins.into_iter()
                .map(|(sum, count)| (count > 0).then(|| sum / f64::from(count)))
                .collect()
        });
        details.cpu_history = cpu;
        details.gpu_history = gpu;
        details.download_history = down;
        details.upload_history = up;
    }
}

type Counters = HashMap<String, (u64, u64)>;
type LocalDay = (i32, u32, u32);

#[derive(Default)]
pub(crate) struct DailyTraffic {
    // shortcut: totals cover the running session, persist baselines if totals must survive restart.
    day: Option<LocalDay>,
    bytes: Option<(u64, u64)>,
    partial: bool,
}

impl DailyTraffic {
    pub(crate) fn record(
        &mut self,
        time: &NaiveDateTime,
        selected: &[&NetworkSnapshot],
        previous: &Counters,
        current: &Counters,
        details: &mut ResourceDetails,
    ) {
        details.network_label = match selected {
            [] => String::new(),
            [link] => {
                let name = &link.name;
                let path = Path::new("/sys/class/net").join(name);
                if path.join("wireless").exists() || path.join("phy80211").exists() {
                    format!("Wi-Fi · {name}")
                } else if link.is_physical && name.starts_with("en") {
                    format!("Ethernet · {name}")
                } else {
                    name.clone()
                }
            }
            _ => format!("{} interfaces", selected.len()),
        };
        let day = (time.year(), time.month(), time.day());
        if self.day != Some(day) {
            self.partial =
                self.day.is_none() || time.hour() != 0 || time.minute() != 0 || time.second() > 1;
            self.day = Some(day);
            // The counter interval crossing midnight cannot be split by date.
            self.bytes = None;
        } else {
            for link in selected {
                let delta = (|| {
                    let &(rx, tx) = current.get(&link.name)?;
                    let &(old_rx, old_tx) = previous.get(&link.name)?;
                    Some((rx.checked_sub(old_rx)?, tx.checked_sub(old_tx)?))
                })();
                if let Some((rx, tx)) = delta {
                    let (down, up) = self.bytes.get_or_insert((0, 0));
                    *down = down.saturating_add(rx);
                    *up = up.saturating_add(tx);
                } else {
                    self.partial = true;
                }
            }
        }
        details.network_today_download_bytes = self.bytes.map(|(rx, _)| rx as f64);
        details.network_today_upload_bytes = self.bytes.map(|(_, tx)| tx as f64);
        details.network_today_partial = self.partial;
    }
}

pub(crate) fn hardware_details(memory: &HashMap<String, u64>) -> ResourceDetails {
    let (cached, free) = memory_breakdown(memory).unzip();
    ResourceDetails {
        memory_cached_bytes: cached.map(|bytes| bytes as f64),
        memory_free_bytes: free.map(|bytes| bytes as f64),
        ..Default::default()
    }
}

fn memory_breakdown(memory: &HashMap<String, u64>) -> Option<(u64, u64)> {
    let available = *memory.get("MemAvailable")?;
    let free = *memory.get("MemFree")?;
    let cache = memory
        .get("Cached")?
        .saturating_add(*memory.get("SReclaimable").unwrap_or(&0))
        .saturating_sub(*memory.get("Shmem").unwrap_or(&0))
        .min(available.saturating_sub(free));
    Some((cache, available - cache))
}

pub(crate) fn cpu_topology(info: &str) -> Option<u32> {
    let mut physical = HashSet::new();
    let mut logical = 0;
    let mut mapped = 0;
    for cpu in info.split("\n\n") {
        let mut socket = None;
        let mut core = None;
        for (key, value) in cpu.lines().filter_map(|line| line.split_once(':')) {
            let value = value.trim();
            match key.trim() {
                "physical id" => socket = value.parse::<u32>().ok(),
                "core id" => core = value.parse::<u32>().ok(),
                "processor" if value.parse::<u32>().is_ok() => logical += 1,
                _ => {}
            }
        }
        if let Some(core) = socket.zip(core) {
            physical.insert(core);
            mapped += 1;
        }
    }
    // A core count is only reported when the kernel publishes the topology.
    (logical > 0 && mapped == logical).then_some(physical.len() as u32)
}

pub(crate) fn cpu_frequency(info: &str) -> Option<f64> {
    let mut sum = 0.0;
    let mut count = 0;
    for (key, value) in info.lines().filter_map(|line| line.split_once(':')) {
        if key.trim() == "cpu MHz"
            && let Ok(value) = value.trim().parse::<f64>()
            && value.is_finite()
            && value > 0.0
        {
            sum += value;
            count += 1;
        }
    }
    (count > 0).then(|| sum / f64::from(count) / 1000.0)
}

#[derive(Default)]
pub(crate) struct TemperatureSensors {
    discovered: Option<Instant>,
    paths: Vec<(PathBuf, bool)>,
}

impl TemperatureSensors {
    pub(crate) fn read(&mut self, root: &Path, drivers: &[&str], labels: &[&str]) -> Option<f64> {
        if self
            .discovered
            .is_none_or(|time| time.elapsed() >= SENSOR_DISCOVERY)
        {
            self.discovered = Some(Instant::now());
            self.paths = temperature_paths(root, drivers, labels);
        }
        let mut preferred = None::<f64>;
        let mut fallback = None::<f64>;
        for (path, is_preferred) in &self.paths {
            let Some(value) = read_number(path).map(|value| value / 1000.0) else {
                // A removed or failing sensor needs discovery again on the next read.
                self.discovered = None;
                continue;
            };
            let target = if *is_preferred {
                &mut preferred
            } else {
                &mut fallback
            };
            *target = Some(target.map_or(value, |old| old.max(value)));
        }
        preferred.or(fallback)
    }
}

fn temperature_paths(root: &Path, drivers: &[&str], labels: &[&str]) -> Vec<(PathBuf, bool)> {
    let mut result = vec![];
    let Ok(entries) = fs::read_dir(root) else {
        return result;
    };
    for device in entries.flatten() {
        let path = device.path();
        let name = fs::read_to_string(path.join("name")).unwrap_or_default();
        if !drivers.contains(&name.trim()) {
            continue;
        }
        let Ok(sensors) = fs::read_dir(&path) else {
            continue;
        };
        for sensor in sensors.flatten() {
            let name = sensor.file_name();
            let name = name.to_string_lossy();
            let Some(id) = name
                .strip_suffix("_input")
                .filter(|id| id.starts_with("temp"))
            else {
                continue;
            };
            let label = fs::read_to_string(path.join(format!("{id}_label"))).unwrap_or_default();
            result.push((
                sensor.path(),
                labels.iter().any(|prefix| label.starts_with(prefix)),
            ));
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_is_reclaimable_and_fits_in_available_memory() {
        let memory = [
            ("MemAvailable", 60),
            ("MemFree", 30),
            ("Cached", 90),
            ("Shmem", 10),
        ]
        .into_iter()
        .map(|(key, value)| (key.into(), value))
        .collect();
        assert_eq!(memory_breakdown(&memory), Some((30, 30)));
    }

    #[test]
    fn traffic_drops_reset_intervals_and_restarts_at_local_midnight() {
        let time = chrono::NaiveDate::from_ymd_opt(2026, 11, 1)
            .unwrap()
            .and_hms_opt(12, 0, 0)
            .unwrap();
        let link = NetworkSnapshot {
            name: "test0".into(),
            is_physical: false,
            download_bytes_per_second: None,
            upload_bytes_per_second: None,
        };
        let mut traffic = DailyTraffic::default();
        let mut details = ResourceDetails::default();
        let first = Counters::from([("test0".into(), (100, 70))]);
        let next = Counters::from([("test0".into(), (130, 80))]);
        traffic.record(&time, &[&link], &Counters::new(), &first, &mut details);
        assert!(details.network_today_partial);
        assert_eq!(details.network_today_download_bytes, None);
        traffic.record(&time, &[&link], &first, &next, &mut details);
        assert_eq!(details.network_today_download_bytes, Some(30.0));
        assert_eq!(details.network_today_upload_bytes, Some(10.0));
        traffic.record(&time, &[&link], &next, &first, &mut details);
        assert_eq!(details.network_today_download_bytes, Some(30.0));
        let time = time
            .date()
            .succ_opt()
            .unwrap()
            .and_hms_opt(0, 0, 0)
            .unwrap();
        traffic.record(&time, &[&link], &first, &next, &mut details);
        assert_eq!(details.network_today_download_bytes, None);
        assert!(!details.network_today_partial);
    }

    #[test]
    fn snapshots_include_cached_history_without_repeating_gpu_reads() {
        let time = Instant::now();
        let mut history = History::default();
        let mut snapshot = crate::metrics::Sampler::default().sample().unwrap().1;
        snapshot.gpus.push(crate::api::GpuSnapshot {
            id: "gpu".into(),
            name: "GPU".into(),
            utilization_percent: Some(50.0),
            memory_used_bytes: None,
            memory_total_bytes: None,
            temperature_celsius: None,
        });
        let window = Duration::from_secs(60);
        let refresh = Duration::from_secs(1);
        snapshot.cpu_percent = Some(42.0);
        history.record(time, window, refresh, &mut snapshot, true);
        let later = time + Duration::from_secs(5);
        snapshot.cpu_percent = Some(12.0);
        history.record(later, window, refresh, &mut snapshot, false);
        let details = snapshot.resources.as_ref().unwrap();
        assert_eq!(details.cpu_history[BARS - 2], Some(42.0));
        assert_eq!(details.cpu_history[BARS - 1], Some(12.0));
        assert_eq!(details.gpu_history[BARS - 2], Some(50.0));
        assert_eq!(details.gpu_history[BARS - 1], None);
    }

    #[test]
    fn temperature_paths_are_reused_until_a_sensor_disappears() {
        let root = tempfile::tempdir().unwrap();
        let device = root.path().join("hwmon0");
        fs::create_dir(&device).unwrap();
        fs::write(device.join("name"), "coretemp").unwrap();
        let first = device.join("temp1_input");
        fs::write(&first, "65000").unwrap();
        let mut sensors = TemperatureSensors::default();
        let read = |sensors: &mut TemperatureSensors| sensors.read(root.path(), &["coretemp"], &[]);
        assert_eq!(read(&mut sensors), Some(65.0));
        fs::write(&first, "70000").unwrap();
        assert_eq!(read(&mut sensors), Some(70.0));
        fs::remove_file(&first).unwrap();
        fs::write(device.join("temp2_input"), "72000").unwrap();
        assert_eq!(read(&mut sensors), None);
        assert_eq!(read(&mut sensors), Some(72.0));
    }

    #[test]
    fn history_keeps_missing_bins_and_expires_after_sixty_seconds() {
        let time = Instant::now();
        let mut history = History::default();
        history.points.push_back(Point {
            time,
            gpu_id: None,
            values: [Some(42.0), None, None, None],
        });
        let mut snapshot = crate::metrics::Sampler::default().sample().unwrap().1;
        snapshot.cpu_percent = None;
        let window = Duration::from_secs(60);
        let refresh = Duration::from_secs(1);
        let almost_expired = time + Duration::from_secs(59);
        history.record(almost_expired, window, refresh, &mut snapshot, false);
        let values = &snapshot.resources.as_ref().unwrap().cpu_history;
        assert_eq!(values[0], Some(42.0));
        assert!(values[1..].iter().all(Option::is_none));
        history.record(time + window, window, refresh, &mut snapshot, false);
        assert!(
            snapshot
                .resources
                .as_ref()
                .unwrap()
                .cpu_history
                .iter()
                .all(Option::is_none)
        );
        // Switching to a 5-minute window reveals earlier samples retained up to MAX_WINDOW.
        history.record(
            time + window,
            Duration::from_secs(300),
            refresh,
            &mut snapshot,
            false,
        );
        assert!(
            snapshot
                .resources
                .as_ref()
                .unwrap()
                .cpu_history
                .contains(&Some(42.0))
        );
    }

    #[test]
    fn history_bins_scale_with_window_and_refresh_rate() {
        let time = Instant::now();
        let mut history = History::default();
        let mut snapshot = crate::metrics::Sampler::default().sample().unwrap().1;

        // 30s window at 5s refresh rate -> 6 evenly spaced bins (no gaps).
        let window = Duration::from_secs(30);
        let refresh = Duration::from_secs(5);
        for step in 0..6 {
            snapshot.cpu_percent = Some((step + 1) as f64 * 10.0);
            history.record(
                time + Duration::from_secs(step * 5),
                window,
                refresh,
                &mut snapshot,
                false,
            );
        }
        assert_eq!(
            snapshot.resources.as_ref().unwrap().cpu_history,
            vec![
                Some(10.0),
                Some(20.0),
                Some(30.0),
                Some(40.0),
                Some(50.0),
                Some(60.0),
            ]
        );

        // 30s window at 500ms refresh rate caps cleanly at 18 bars.
        snapshot.cpu_percent = Some(75.0);
        history.record(
            time + Duration::from_secs(26),
            Duration::from_secs(30),
            Duration::from_millis(500),
            &mut snapshot,
            false,
        );
        assert_eq!(snapshot.resources.as_ref().unwrap().cpu_history.len(), BARS);
    }
}
