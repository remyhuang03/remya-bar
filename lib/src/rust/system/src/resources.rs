use crate::api::{ResourceDetails, SystemSnapshot};
use crate::metrics::NetworkSnapshot;
use crate::metrics::read_number;
use chrono::{Datelike, NaiveDateTime, Timelike};
use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::path::Path;
use std::time::{Duration, Instant};

const BARS: usize = 18;
const WINDOW: Duration = Duration::from_secs(60);

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
    pub(crate) fn record(&mut self, time: Instant, snapshot: &mut SystemSnapshot) {
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
        self.gpu_id = gpu.map(|gpu| gpu.id.clone());
        details.gpu_id = self.gpu_id.clone();
        let network = snapshot.network_overview.as_ref();
        self.points.push_back(Point {
            time,
            gpu_id: self.gpu_id.clone(),
            values: [
                snapshot.cpu_percent,
                gpu.and_then(|gpu| gpu.utilization_percent),
                network.and_then(|network| network.download_bytes_per_second),
                network.and_then(|network| network.upload_bytes_per_second),
            ],
        });
        while self
            .points
            .front()
            .is_some_and(|point| time.duration_since(point.time) >= WINDOW)
        {
            self.points.pop_front();
        }

        let mut bins = [[(0.0, 0u32); BARS]; 4];
        for point in &self.points {
            let age = time.duration_since(point.time).as_millis();
            let index = BARS - 1 - (age * BARS as u128 / WINDOW.as_millis()) as usize;
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
    let (cores, frequency) = cpu_topology();
    ResourceDetails {
        cpu_cores: cores,
        cpu_frequency_ghz: frequency,
        cpu_temperature_celsius: hwmon_temperature(
            Path::new("/sys/class/hwmon"),
            &[
                "coretemp",
                "k10temp",
                "zenpower",
                "cpu_thermal",
                "cpu-thermal",
            ],
            &["Package id", "Tdie", "Tctl"],
        ),
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

fn cpu_topology() -> (Option<u32>, Option<f64>) {
    let info = fs::read_to_string("/proc/cpuinfo").unwrap_or_default();
    let mut physical = HashSet::new();
    let mut logical = 0;
    let mut mapped = 0;
    let (mut mhz, mut count) = (0.0, 0);
    for cpu in info.split("\n\n") {
        let mut socket = None;
        let mut core = None;
        for (key, value) in cpu.lines().filter_map(|line| line.split_once(':')) {
            let value = value.trim();
            match key.trim() {
                "physical id" => socket = value.parse::<u32>().ok(),
                "core id" => core = value.parse::<u32>().ok(),
                "processor" if value.parse::<u32>().is_ok() => logical += 1,
                "cpu MHz" => {
                    if let Ok(value) = value.parse::<f64>()
                        && value.is_finite()
                        && value > 0.0
                    {
                        mhz += value;
                        count += 1;
                    }
                }
                _ => {}
            }
        }
        if let Some(core) = socket.zip(core) {
            physical.insert(core);
            mapped += 1;
        }
    }
    // A core count is only reported when the kernel publishes the topology.
    let cores = (logical > 0 && mapped == logical).then_some(physical.len() as u32);
    let frequency = (count > 0).then(|| mhz / f64::from(count) / 1000.0);
    (cores, frequency)
}

pub(crate) fn hwmon_temperature(root: &Path, drivers: &[&str], labels: &[&str]) -> Option<f64> {
    let mut preferred = None::<f64>;
    let mut fallback = None::<f64>;
    for device in fs::read_dir(root).ok()?.flatten() {
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
            let Some(value) = read_number(sensor.path()).map(|value| value / 1000.0) else {
                continue;
            };
            let label = fs::read_to_string(path.join(format!("{id}_label"))).unwrap_or_default();
            let target = if labels.iter().any(|prefix| label.starts_with(prefix)) {
                &mut preferred
            } else {
                &mut fallback
            };
            *target = Some(target.map_or(value, |old| old.max(value)));
        }
    }
    preferred.or(fallback)
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
        history.record(time + Duration::from_secs(59), &mut snapshot);
        let values = &snapshot.resources.as_ref().unwrap().cpu_history;
        assert_eq!(values[0], Some(42.0));
        assert!(values[1..].iter().all(Option::is_none));
        history.record(time + WINDOW, &mut snapshot);
        assert!(
            snapshot
                .resources
                .unwrap()
                .cpu_history
                .iter()
                .all(Option::is_none)
        );
    }
}
