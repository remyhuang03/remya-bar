use std::{fs, path::Path};

#[derive(Clone, Debug)]
pub struct BatterySnapshot {
    pub name: String,
    pub percent: Option<f64>,
    pub state: String,
    pub remaining_seconds: Option<f64>,
    pub power_watts: Option<f64>,
    pub health_percent: Option<f64>,
    pub cycle_count: Option<i32>,
}

pub fn batteries() -> Vec<BatterySnapshot> {
    let Ok(entries) = fs::read_dir("/sys/class/power_supply") else {
        return vec![];
    };
    let mut result = vec![];
    for entry in entries.flatten() {
        let path = entry.path();
        if fs::read_to_string(path.join("type"))
            .unwrap_or_default()
            .trim()
            != "Battery"
            || read_number(path.join("present")) == Some(0.0)
        {
            continue;
        }
        // Peripheral batteries do not represent the workstation's remaining power.
        if fs::read_to_string(path.join("scope"))
            .unwrap_or_default()
            .trim()
            == "Device"
        {
            continue;
        }
        let state = fs::read_to_string(path.join("status"))
            .unwrap_or_else(|_| "Unknown".into())
            .trim()
            .to_owned();
        let energy = read_number(path.join("energy_now"));
        let full = read_number(path.join("energy_full"));
        let charge = read_number(path.join("charge_now"));
        let charge_full = read_number(path.join("charge_full"));
        let power = read_number(path.join("power_now"));
        let current = read_number(path.join("current_now"));
        let voltage = read_number(path.join("voltage_now"));
        let percent = read_number(path.join("capacity"))
            .or_else(|| percentage(energy, full))
            .or_else(|| percentage(charge, charge_full))
            .filter(|v| *v <= 100.0);
        result.push(BatterySnapshot {
            name: entry.file_name().to_string_lossy().into_owned(),
            percent,
            remaining_seconds: remaining_seconds(&state, energy, full, power)
                .or_else(|| remaining_seconds(&state, charge, charge_full, current)),
            power_watts: power
                .map(|v| v / 1e6)
                .or_else(|| current.zip(voltage).map(|(a, v)| a * v / 1e12)),
            health_percent: percentage(full, read_number(path.join("energy_full_design")))
                .or_else(|| percentage(charge_full, read_number(path.join("charge_full_design")))),
            cycle_count: fs::read_to_string(path.join("cycle_count"))
                .ok()
                .and_then(|value| value.trim().parse::<i32>().ok())
                .filter(|count| *count >= 0),
            state,
        });
    }
    result.sort_by(|a, b| a.name.cmp(&b.name));
    result
}

fn remaining_seconds(
    state: &str,
    now: Option<f64>,
    full: Option<f64>,
    rate: Option<f64>,
) -> Option<f64> {
    let rate = rate.filter(|v| *v > 0.0)?;
    let value = match state {
        "Charging" => (full? - now?).max(0.0),
        "Discharging" => now?,
        _ => return None,
    };
    Some(value / rate * 3600.0)
}

fn read_number(path: impl AsRef<Path>) -> Option<f64> {
    let number: f64 = fs::read_to_string(path).ok()?.trim().parse().ok()?;
    (number.is_finite() && number >= 0.0).then_some(number)
}

fn percentage(value: Option<f64>, total: Option<f64>) -> Option<f64> {
    let total = total.filter(|v| *v > 0.0)?;
    Some(value? / total * 100.0)
}

#[derive(Clone, Debug)]
pub struct MediaPlayerSnapshot {
    pub bus_name: String,
    pub identity: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub art_url: String,
    pub playback_status: String,
    pub can_control: bool,
    pub can_go_next: bool,
    pub can_go_previous: bool,
    pub can_play: bool,
    pub can_pause: bool,
    pub seek_token: Option<String>,
    pub position_seconds: Option<f64>,
    pub length_seconds: Option<f64>,
}

pub async fn media_players() -> Result<Vec<MediaPlayerSnapshot>, String> {
    crate::media::players().await
}

pub async fn media_action(bus_name: String, action: String) -> Result<(), String> {
    crate::media::action(&bus_name, &action, None).await
}

pub async fn media_seek(bus_name: String, track: String, seconds: f64) -> Result<(), String> {
    crate::media::action(&bus_name, "seek", Some((&track, seconds))).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn battery_estimates_require_known_state_and_positive_rate() {
        assert_eq!(
            remaining_seconds("Charging", Some(20.0), Some(50.0), Some(10.0)),
            Some(10800.0)
        );
        assert_eq!(
            remaining_seconds("Discharging", Some(20.0), None, Some(10.0)),
            Some(7200.0)
        );
        assert_eq!(
            remaining_seconds("Full", Some(50.0), Some(50.0), Some(10.0)),
            None
        );
        assert_eq!(
            remaining_seconds("Discharging", Some(20.0), None, Some(0.0)),
            None
        );
        assert_eq!(
            remaining_seconds("Charging", Some(51.0), Some(50.0), Some(10.0)),
            Some(0.0)
        );
    }
}
