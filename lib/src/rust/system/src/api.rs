use std::sync::OnceLock;
use std::time::{Duration, Instant};
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

pub(crate) fn batteries() -> Vec<BatterySnapshot> {
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

#[derive(Clone, Debug, PartialEq)]
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

pub async fn subscribe_media(sink: crate::frb_generated::StreamSink<Vec<MediaPlayerSnapshot>>) {
    crate::media::subscribe(sink).await;
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

#[derive(Clone, Debug)]
pub struct TrayItem {
    pub id: String,
    pub app_id: String,
    pub icon_theme_path: String,
    pub title: String,
    pub icon_name: String,
    pub icon_argb: Vec<u8>,
    pub icon_width: u32,
    pub icon_height: u32,
    pub item_is_menu: bool,
    pub has_menu: bool,
    pub attention: bool,
}
#[derive(Clone, Debug)]
pub struct TrayMenuEntry {
    pub id: i32,
    pub label: String,
    pub enabled: bool,
    pub separator: bool,
    pub submenu: bool,
    pub icon_name: String,
    pub icon_data: Vec<u8>,
    pub toggle_type: String,
    pub toggle_state: i32,
}
pub async fn tray_items() -> Result<Vec<TrayItem>, String> {
    crate::tray::items().await
}
pub async fn tray_action(id: String, action: String, delta: i32) -> Result<(), String> {
    crate::tray::action(&id, &action, delta).await
}
pub async fn tray_menu(id: String, parent: i32) -> Result<Vec<TrayMenuEntry>, String> {
    crate::tray::menu(&id, parent).await
}
pub async fn tray_menu_action(id: String, parent: i32, entry: i32) -> Result<(), String> {
    crate::tray::menu_action(&id, parent, entry).await
}

#[derive(Clone, Debug)]
pub struct SystemSnapshot {
    pub batteries: Vec<BatterySnapshot>,
    pub cpu_percent: Option<f64>,
    pub memory_used_bytes: Option<f64>,
    pub memory_total_bytes: Option<f64>,
    pub swap_used_bytes: Option<f64>,
    pub swap_total_bytes: Option<f64>,
    pub gpus: Vec<GpuSnapshot>,
    pub network_overview: Option<NetworkOverview>,
    pub resources: Option<ResourceDetails>,
}

#[derive(Clone, Debug)]
pub struct GpuSnapshot {
    pub id: String,
    pub name: String,
    pub utilization_percent: Option<f64>,
    pub memory_used_bytes: Option<f64>,
    pub memory_total_bytes: Option<f64>,
    pub temperature_celsius: Option<f64>,
}

#[derive(Clone, Debug, Default)]
pub struct ResourceDetails {
    pub cpu_cores: Option<u32>,
    pub cpu_frequency_ghz: Option<f64>,
    pub cpu_temperature_celsius: Option<f64>,
    pub gpu_id: Option<String>,
    pub memory_cached_bytes: Option<f64>,
    pub memory_free_bytes: Option<f64>,
    pub network_label: String,
    pub network_today_download_bytes: Option<f64>,
    pub network_today_upload_bytes: Option<f64>,
    pub network_today_partial: bool,
    pub cpu_history: Vec<Option<f64>>,
    pub gpu_history: Vec<Option<f64>>,
    pub download_history: Vec<Option<f64>>,
    pub upload_history: Vec<Option<f64>>,
}

#[derive(Clone, Debug)]
pub struct NetworkOverview {
    pub download_bytes_per_second: Option<f64>,
    pub upload_bytes_per_second: Option<f64>,
}

/// All output engines share one sample and one set of CPU/network baselines.
pub async fn hardware_snapshot() -> Result<SystemSnapshot, String> {
    #[derive(Default)]
    struct Cache {
        updated: Option<Instant>,
        snapshot: Option<SystemSnapshot>,
        resources: crate::resources::History,
    }
    static CACHE: OnceLock<tokio::sync::Mutex<Cache>> = OnceLock::new();
    static SAMPLER: OnceLock<std::sync::Mutex<crate::metrics::Sampler>> = OnceLock::new();
    let mut cache = CACHE.get_or_init(Default::default).lock().await;
    if cache
        .updated
        .is_some_and(|time| time.elapsed() < Duration::from_millis(900))
    {
        return Ok(cache.snapshot.as_ref().unwrap().clone());
    }
    let (sampled_at, mut snapshot) = tokio::task::spawn_blocking(|| {
        SAMPLER
            .get_or_init(Default::default)
            .lock()
            .map_err(|error| error.to_string())?
            .sample()
    })
    .await
    .map_err(|error| error.to_string())??;
    let gpus = crate::metrics::nvidia_gpus().await;
    if let Ok(gpus) = gpus {
        // The NVIDIA tool provides a richer identity than the matching DRM entry.
        snapshot.gpus.retain(|gpu| !gpu.id.starts_with("nvidia:"));
        snapshot.gpus.extend(gpus);
    }
    cache.resources.record(sampled_at, &mut snapshot);
    cache.updated = Some(Instant::now());
    cache.snapshot = Some(snapshot.clone());
    Ok(snapshot)
}

pub async fn sidebar_session_action(action: String) -> Result<(), String> {
    crate::session::action(&action).await
}

pub fn sidebar_uptime() -> Option<f64> {
    let uptime = std::fs::read_to_string("/proc/uptime").ok()?;
    uptime
        .split_whitespace()
        .next()?
        .parse::<f64>()
        .ok()
        .filter(|value| value.is_finite() && *value >= 0.0)
}

/// A run of notification body text with the supported markup applied.
#[derive(Clone, Debug, PartialEq)]
pub struct NotificationText {
    pub text: String,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    /// An http(s) or mailto link; empty when the run is not a link.
    pub href: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct NotificationAction {
    pub key: String,
    pub label: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct NotificationSnapshot {
    pub id: u32,
    pub app_name: String,
    pub app_icon: String,
    pub desktop_entry: String,
    pub summary: String,
    pub body: Vec<NotificationText>,
    /// Button actions; the `default` action is reported separately.
    pub actions: Vec<NotificationAction>,
    pub default_action: bool,
    /// 0 Low, 1 Normal, 2 Critical.
    pub urgency: u8,
    pub received_unix_ms: i64,
    /// `image-data` as tray-compatible ARGB; empty when absent.
    pub image_argb: Vec<u8>,
    pub image_width: u32,
    pub image_height: u32,
    pub image_path: String,
    pub progress: Option<i32>,
    /// Whether the notification is currently shown as a popup.
    pub popup: bool,
    pub transient: bool,
    pub resident: bool,
    /// The freedesktop `category` hint, such as `call.incoming`.
    pub category: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct NotificationCenter {
    /// Newest first.
    pub notifications: Vec<NotificationSnapshot>,
    /// Why Do Not Disturb is in effect: empty, `manual`, `schedule` or
    /// `fullscreen`.
    pub quiet_reason: String,
    /// The output that shows the popup stack, if any.
    pub popup_host: Option<String>,
    /// Set while the bar does not own the notification service name.
    pub error: Option<String>,
}

/// Starts the shared notification server and streams its state.
pub async fn subscribe_notifications(sink: crate::frb_generated::StreamSink<NotificationCenter>) {
    crate::notifications::subscribe(sink).await;
}

#[derive(Clone, Debug, PartialEq)]
pub struct NotificationPriorityApp {
    pub id: String,
    pub name: String,
}

/// Settings notification preferences; times are minutes after midnight and
/// days are ISO weekdays (1 Monday) on which the schedule starts.
#[derive(Clone, Debug, PartialEq)]
pub struct NotificationPreferences {
    pub do_not_disturb: bool,
    pub timeout_seconds: u32,
    pub sounds: bool,
    pub schedule: bool,
    pub schedule_start_minutes: u32,
    pub schedule_end_minutes: u32,
    pub schedule_days: Vec<u32>,
    pub fullscreen: bool,
    pub priority_calls: bool,
    pub priority_apps: Vec<NotificationPriorityApp>,
}

pub async fn notifications_configure(preferences: NotificationPreferences) {
    crate::notifications::configure(preferences).await;
}

/// Reports whether an output shows a full screen window.
pub async fn notifications_fullscreen(output: String, fullscreen: bool) {
    crate::notifications::fullscreen(output, fullscreen).await;
}

/// Claims the popup stack for an output; false when another output hosts it.
pub async fn notifications_claim_popups(output: String) -> bool {
    crate::notifications::claim_popups(output).await
}

/// Pauses popup expiry while the pointer is over the popups.
pub async fn notifications_hover(hovered: bool) {
    crate::notifications::hover(hovered).await;
}

/// Dismisses one notification, or all of them when `id` is null.
pub async fn notification_dismiss(id: Option<u32>) -> Result<(), String> {
    crate::notifications::dismiss(id).await
}

pub async fn notification_invoke(id: u32, action: String) -> Result<(), String> {
    crate::notifications::invoke(id, &action).await
}
