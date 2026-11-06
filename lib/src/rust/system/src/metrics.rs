use crate::api::*;
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::time::{Duration, Instant};

#[derive(Clone, Debug)]
pub(crate) struct NetworkSnapshot {
    pub name: String,
    pub is_physical: bool,
    pub download_bytes_per_second: Option<f64>,
    pub upload_bytes_per_second: Option<f64>,
}

#[derive(Default)]
pub(crate) struct Sampler {
    cpu: Option<(u64, u64)>,
    networks: HashMap<String, (u64, u64)>,
    sampled: Option<Instant>,
    traffic: crate::resources::DailyTraffic,
}

impl Sampler {
    pub(crate) fn sample(&mut self) -> Result<(Instant, SystemSnapshot), String> {
        let now = Instant::now();
        let cpu = parse_cpu(&fs::read_to_string("/proc/stat").map_err(|e| e.to_string())?);
        let cpu_percent = self.cpu.zip(cpu).and_then(|(old, new)| cpu_delta(old, new));
        self.cpu = cpu;
        let memory = parse_memory(&fs::read_to_string("/proc/meminfo").map_err(|e| e.to_string())?);
        let current = fs::read_to_string("/proc/net/dev")
            .map(|s| parse_networks(&s))
            .map_err(|e| e.to_string())?;
        let elapsed = self
            .sampled
            .map(|time| now.duration_since(time).as_secs_f64());
        let mut networks: Vec<_> = current
            .iter()
            .map(|(name, &(rx, tx))| {
                let previous = self.networks.get(name);
                NetworkSnapshot {
                    name: name.clone(),
                    is_physical: Path::new("/sys/class/net")
                        .join(name)
                        .join("device")
                        .exists(),
                    download_bytes_per_second: previous
                        .zip(elapsed)
                        .and_then(|(old, seconds)| rate(old.0, rx, seconds)),
                    upload_bytes_per_second: previous
                        .zip(elapsed)
                        .and_then(|(old, seconds)| rate(old.1, tx, seconds)),
                }
            })
            .collect();
        networks.sort_by(|a, b| a.name.cmp(&b.name));
        let selected = network_selection(&networks);
        let overview = network_overview(&selected);
        let date_time = chrono::Local::now().naive_local();
        let mut resources = crate::resources::hardware_details(&memory);
        self.traffic.record(
            &date_time,
            &selected,
            &self.networks,
            &current,
            &mut resources,
        );
        self.networks = current;
        self.sampled = Some(now);
        Ok((
            now,
            SystemSnapshot {
                cpu_percent,
                memory_used_bytes: memory
                    .get("MemTotal")
                    .zip(memory.get("MemAvailable"))
                    .and_then(|(total, free)| total.checked_sub(*free))
                    .map(|v| v as f64),
                memory_total_bytes: memory.get("MemTotal").map(|v| *v as f64),
                swap_used_bytes: memory
                    .get("SwapTotal")
                    .zip(memory.get("SwapFree"))
                    .and_then(|(total, free)| total.checked_sub(*free))
                    .map(|v| v as f64),
                swap_total_bytes: memory.get("SwapTotal").map(|v| *v as f64),
                gpus: drm_gpus(),
                network_overview: Some(overview),
                resources: Some(resources),
            },
        ))
    }
}

fn network_selection(networks: &[NetworkSnapshot]) -> Vec<&NetworkSnapshot> {
    let physical: Vec<_> = networks
        .iter()
        .filter(|network| network.is_physical)
        .collect();
    if physical.is_empty() {
        networks
            .iter()
            .max_by(|a, b| {
                let traffic = |network: &NetworkSnapshot| {
                    network.download_bytes_per_second.unwrap_or(0.0)
                        + network.upload_bytes_per_second.unwrap_or(0.0)
                };
                traffic(a).total_cmp(&traffic(b))
            })
            .into_iter()
            .collect()
    } else {
        let active: Vec<_> = physical
            .iter()
            .copied()
            .filter(|network| {
                fs::read_to_string(
                    Path::new("/sys/class/net")
                        .join(&network.name)
                        .join("operstate"),
                )
                .is_ok_and(|state| state.trim() == "up")
            })
            .collect();
        if active.is_empty() { physical } else { active }
    }
}

fn network_overview(selected: &[&NetworkSnapshot]) -> NetworkOverview {
    let sum = |download: bool| {
        if selected.is_empty() {
            return None;
        }
        selected.iter().try_fold(0.0, |total, network| {
            let value = if download {
                network.download_bytes_per_second
            } else {
                network.upload_bytes_per_second
            }?;
            (value.is_finite() && value >= 0.0).then_some(total + value)
        })
    };
    NetworkOverview {
        download_bytes_per_second: sum(true),
        upload_bytes_per_second: sum(false),
    }
}

fn parse_cpu(text: &str) -> Option<(u64, u64)> {
    let mut fields = text.lines().next()?.split_whitespace();
    if fields.next()? != "cpu" {
        return None;
    }
    // Guest ticks are already counted in user/nice and must not be added twice.
    let ticks: Vec<u64> = fields
        .take(8)
        .map(str::parse)
        .collect::<Result<_, _>>()
        .ok()?;
    if ticks.len() < 4 {
        return None;
    }
    Some((
        ticks.iter().try_fold(0u64, |sum, n| sum.checked_add(*n))?,
        ticks[3].checked_add(*ticks.get(4).unwrap_or(&0))?,
    ))
}

fn cpu_delta(old: (u64, u64), new: (u64, u64)) -> Option<f64> {
    let total = new.0.checked_sub(old.0)?;
    let idle = new.1.checked_sub(old.1)?;
    if total == 0 || idle > total {
        return None;
    }
    Some((total - idle) as f64 / total as f64 * 100.0)
}

fn rate(old: u64, new: u64, seconds: f64) -> Option<f64> {
    if !seconds.is_finite() || seconds <= 0.0 {
        return None;
    }
    Some(new.checked_sub(old)? as f64 / seconds)
}

fn parse_memory(text: &str) -> HashMap<String, u64> {
    text.lines()
        .filter_map(|line| {
            let (name, value) = line.split_once(':')?;
            let mut fields = value.split_whitespace();
            let value: u64 = fields.next()?.parse().ok()?;
            (fields.next()? == "kB")
                .then(|| value.checked_mul(1024))
                .flatten()
                .map(|value| (name.into(), value))
        })
        .collect()
}

fn parse_networks(text: &str) -> HashMap<String, (u64, u64)> {
    text.lines()
        .filter_map(|line| {
            let (name, value) = line.split_once(':')?;
            let name = name.trim();
            if name == "lo" || name.is_empty() {
                return None;
            }
            let values: Vec<_> = value.split_whitespace().collect();
            Some((
                name.into(),
                (values.first()?.parse().ok()?, values.get(8)?.parse().ok()?),
            ))
        })
        .collect()
}

pub(crate) fn read_number(path: impl AsRef<Path>) -> Option<f64> {
    let number: f64 = fs::read_to_string(path).ok()?.trim().parse().ok()?;
    (number.is_finite() && number >= 0.0).then_some(number)
}

fn drm_gpus() -> Vec<GpuSnapshot> {
    let Ok(entries) = fs::read_dir("/sys/class/drm") else {
        return vec![];
    };
    let mut gpus = vec![];
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if !name
            .strip_prefix("card")
            .is_some_and(|s| !s.is_empty() && s.chars().all(|c| c.is_ascii_digit()))
        {
            continue;
        }
        let device = entry.path().join("device");
        let vendor = fs::read_to_string(device.join("vendor")).unwrap_or_default();
        let vendor = vendor.trim();
        let product = fs::read_to_string(device.join("device")).unwrap_or_default();
        let vendor_name = match vendor {
            "0x1002" => "AMD",
            "0x10de" => "NVIDIA",
            "0x8086" => "Intel",
            _ => "GPU",
        };
        gpus.push(GpuSnapshot {
            id: format!(
                "{}:{name}",
                if vendor == "0x10de" { "nvidia" } else { "drm" }
            ),
            name: format!("{vendor_name} {} ({name})", product.trim()),
            utilization_percent: read_number(device.join("gpu_busy_percent"))
                .filter(|v| *v <= 100.0),
            memory_used_bytes: read_number(device.join("mem_info_vram_used")),
            memory_total_bytes: read_number(device.join("mem_info_vram_total")),
            temperature_celsius: crate::resources::hwmon_temperature(
                &device.join("hwmon"),
                &["amdgpu", "i915", "xe", "nouveau"],
                &["edge", "gpu"],
            ),
        });
    }
    gpus.sort_by(|a, b| a.id.cmp(&b.id));
    gpus
}

pub(crate) async fn nvidia_gpus() -> Result<Vec<GpuSnapshot>, String> {
    let mut command = tokio::process::Command::new("nvidia-smi");
    command
        .args([
            "--query-gpu=uuid,name,utilization.gpu,memory.used,memory.total,temperature.gpu",
            "--format=csv,noheader,nounits",
        ])
        .kill_on_drop(true);
    let output = tokio::time::timeout(Duration::from_millis(800), command.output())
        .await
        .map_err(|_| "NVIDIA query timed out")?
        .map_err(|e| e.to_string())?;
    if !output.status.success() {
        return Err("NVIDIA query unavailable".into());
    }
    Ok(parse_nvidia(&String::from_utf8_lossy(&output.stdout)))
}

fn parse_nvidia(text: &str) -> Vec<GpuSnapshot> {
    text.lines()
        .filter_map(|line| {
            let fields: Vec<_> = line.split(',').map(str::trim).collect();
            if fields.len() != 6 || fields[0].is_empty() {
                return None;
            }
            let number = |s: &str| s.parse::<f64>().ok().filter(|v| v.is_finite() && *v >= 0.0);
            Some(GpuSnapshot {
                id: fields[0].into(),
                name: fields[1].into(),
                utilization_percent: number(fields[2]).filter(|v| *v <= 100.0),
                memory_used_bytes: number(fields[3]).map(|v| v * 1024.0 * 1024.0),
                memory_total_bytes: number(fields[4]).map(|v| v * 1024.0 * 1024.0),
                temperature_celsius: number(fields[5]),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn network_overview_sums_physical_interfaces_without_virtual_duplicates() {
        let network = |physical, down, up| NetworkSnapshot {
            name: String::new(),
            is_physical: physical,
            download_bytes_per_second: down,
            upload_bytes_per_second: up,
        };
        let overview =
            |networks: &[NetworkSnapshot]| network_overview(&network_selection(networks));
        let result = overview(&[
            network(true, Some(100.0), Some(200.0)),
            network(true, Some(200.0), None),
            network(false, Some(9999.0), Some(9999.0)),
        ]);
        assert_eq!(result.download_bytes_per_second, Some(300.0));
        assert_eq!(result.upload_bytes_per_second, None);
        let result = overview(&[
            network(false, Some(100.0), Some(100.0)),
            network(false, Some(200.0), Some(200.0)),
        ]);
        assert_eq!(result.download_bytes_per_second, Some(200.0));
        let result = overview(&[
            network(true, None, None),
            network(false, Some(100.0), Some(100.0)),
        ]);
        assert_eq!(result.download_bytes_per_second, None);
        assert_eq!(overview(&[]).download_bytes_per_second, None);
    }

    #[test]
    fn cpu_excludes_double_counted_guests_and_handles_resets() {
        assert_eq!(
            parse_cpu("cpu 100 20 30 400 10 5 6 7 1000 1000\ncpu0 1"),
            Some((578, 410))
        );
        assert_eq!(cpu_delta((100, 60), (200, 80)), Some(80.0));
        assert_eq!(cpu_delta((200, 80), (100, 60)), None);
        assert_eq!(cpu_delta((100, 60), (100, 60)), None);
        assert_eq!(parse_cpu("cpu 1 invalid 3 4"), None);
    }

    #[test]
    fn network_delta_never_spikes_on_reset_or_new_interface() {
        assert_eq!(rate(1000, 3000, 2.0), Some(1000.0));
        assert_eq!(rate(3000, 1000, 1.0), None);
        assert_eq!(rate(0, 1, 0.0), None);
        assert_eq!(rate(0, 1, f64::NAN), None);
        let counters =
            parse_networks("lo: 100 0 0 0 0 0 0 0 200\nwlan0: 1024 0 0 0 0 0 0 0 2048 0\nbroken");
        assert_eq!(counters.len(), 1);
        assert_eq!(counters["wlan0"], (1024, 2048));
    }

    #[test]
    fn memory_parser_rejects_unknown_units_and_overflow() {
        let memory = parse_memory(
            "MemTotal: 2048 kB\nMemAvailable: 512 kB\nBad: 7 MB\nBroken: no kB\nHuge: 18446744073709551615 kB",
        );
        assert_eq!(memory.len(), 2);
        assert_eq!(memory["MemTotal"], 2097152);
        assert_eq!(memory["MemAvailable"], 524288);
    }

    #[test]
    fn nvidia_unsupported_fields_remain_unavailable() {
        let gpus = parse_nvidia(
            "GPU-123, Example GPU, 52, 10, 100, 46\nGPU-456, Other GPU, [N/A], [N/A], [N/A], [N/A]\nmalformed",
        );
        assert_eq!(gpus.len(), 2);
        assert_eq!(gpus[0].utilization_percent, Some(52.0));
        assert_eq!(gpus[0].temperature_celsius, Some(46.0));
        assert_eq!(gpus[0].memory_used_bytes, Some(10485760.0));
        assert_eq!(gpus[1].utilization_percent, None);
        assert_eq!(gpus[1].memory_total_bytes, None);
    }
}
