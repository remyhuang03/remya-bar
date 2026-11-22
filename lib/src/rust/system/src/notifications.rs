//! Process-wide `org.freedesktop.Notifications` server shared by every output.
mod delivery;
mod history;
mod payload;

use crate::api::{NotificationCenter, NotificationPreferences, NotificationSnapshot};
use crate::frb_generated::StreamSink;
use chrono::{Local, NaiveDateTime};
use delivery::{bypasses, next_schedule_boundary, play_sound, scheduled};
use history::History;
use payload::{hint_bool, hint_byte, hint_int, hint_string, image_data, parse_actions, parse_body};
use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{Mutex, Notify, watch};
use zbus::zvariant::OwnedValue;

const NAME: &str = "org.freedesktop.Notifications";
const PATH: &str = "/org/freedesktop/Notifications";
const HISTORY_LIMIT: usize = 200;
const IMAGE_LIMIT: u32 = 128;

const EXPIRED: u32 = 1;
const DISMISSED: u32 = 2;
const CLOSED: u32 = 3;

struct Entry {
    snapshot: NotificationSnapshot,
    order: i64,
    timeout: Option<Duration>,
    deadline: Option<Instant>,
    remaining: Option<Duration>,
}

impl Entry {
    fn hide_popup(&mut self) {
        self.snapshot.popup = false;
        self.deadline = None;
        self.remaining = None;
    }
}

struct Daemon {
    entries: Vec<Entry>,
    next_id: u32,
    popup_sequence: u32,
    history: Option<History>,
    preferences: NotificationPreferences,
    preferences_loaded: bool,
    fullscreen: HashSet<String>,
    quiet: Option<&'static str>,
    hovered: bool,
    /// The output showing the popup stack until it empties.
    popup_host: Option<String>,
    error: Option<String>,
    connection: Option<zbus::Connection>,
}

impl Daemon {
    fn new() -> Self {
        Self {
            entries: Vec::new(),
            next_id: 1,
            popup_sequence: 0,
            history: None,
            preferences: NotificationPreferences {
                do_not_disturb: false,
                clear_critical: false,
                timeout_seconds: 5,
                sounds: true,
                schedule: false,
                schedule_start_minutes: 22 * 60,
                schedule_end_minutes: 7 * 60,
                schedule_days: (1..=7).collect(),
                fullscreen: false,
                priority_calls: true,
                priority_apps: Vec::new(),
            },
            preferences_loaded: false,
            fullscreen: HashSet::new(),
            quiet: None,
            hovered: false,
            popup_host: None,
            error: Some("Notification service starting".into()),
            connection: None,
        }
    }

    fn allocate_id(&mut self) -> u32 {
        loop {
            let id = self.next_id;
            self.next_id = self.next_id.checked_add(1).unwrap_or(1);
            if id != 0 && !self.entries.iter().any(|entry| entry.snapshot.id == id) {
                return id;
            }
        }
    }

    fn center(&self) -> NotificationCenter {
        NotificationCenter {
            notifications: self
                .entries
                .iter()
                .map(|entry| entry.snapshot.clone())
                .collect(),
            do_not_disturb: self
                .preferences_loaded
                .then_some(self.preferences.do_not_disturb),
            quiet_reason: self.quiet.unwrap_or_default().into(),
            quiet_until_minutes: (self.quiet == Some("schedule"))
                .then_some(self.preferences.schedule_end_minutes),
            clear_critical: self.preferences.clear_critical,
            popup_host: self.popup_host.clone(),
            error: self.error.clone(),
        }
    }

    fn update_popup(&mut self, index: usize, alert: bool) {
        let entry = &mut self.entries[index];
        let critical = entry.snapshot.urgency == 2;
        entry.snapshot.popup = (alert || entry.snapshot.popup)
            && entry.snapshot.urgency != 0
            && (self.quiet.is_none() || bypasses(&self.preferences, &entry.snapshot));
        if entry.snapshot.popup && alert {
            self.popup_sequence = self.popup_sequence.wrapping_add(1);
            entry.snapshot.popup_sequence = self.popup_sequence;
        }
        let timeout = entry.timeout.filter(|_| entry.snapshot.popup && !critical);
        if alert || timeout.is_none() {
            entry.remaining = None;
            entry.deadline = None;
        }
        if let Some(timeout) = timeout
            && entry.remaining.is_none()
            && entry.deadline.is_none()
        {
            if self.hovered {
                entry.remaining = Some(timeout);
            } else {
                entry.deadline = Some(Instant::now() + timeout);
            }
        }
    }

    fn receive(
        &mut self,
        mut snapshot: NotificationSnapshot,
        replaces_id: u32,
        timeout: Option<Duration>,
    ) -> (usize, bool) {
        if let Some(index) = self
            .entries
            .iter()
            .position(|entry| replaces_id != 0 && entry.snapshot.id == replaces_id)
        {
            let entry = &mut self.entries[index];
            let alert = entry.snapshot.summary != snapshot.summary;
            snapshot.id = replaces_id;
            snapshot.popup = entry.snapshot.popup;
            snapshot.popup_sequence = entry.snapshot.popup_sequence;
            entry.snapshot = snapshot;
            entry.timeout = timeout;
            self.update_popup(index, alert);
            return (index, false);
        }

        snapshot.id = self.allocate_id();
        self.entries.insert(
            0,
            Entry {
                snapshot,
                order: self
                    .entries
                    .first()
                    .map_or(0, |entry| entry.order.saturating_add(1)),
                timeout,
                deadline: None,
                remaining: None,
            },
        );
        self.update_popup(0, true);
        (0, true)
    }

    fn remove(&mut self, id: u32) -> bool {
        let before = self.entries.len();
        self.entries.retain(|entry| entry.snapshot.id != id);
        self.entries.len() != before
    }

    fn apply_action(&mut self, id: u32, action: &str) -> Result<bool, String> {
        let entry = self
            .entries
            .iter_mut()
            .find(|entry| entry.snapshot.id == id)
            .ok_or("Notification is gone")?;
        let known = if action == "default" {
            entry.snapshot.default_action
        } else {
            entry.snapshot.actions.iter().any(|item| item.key == action)
        };
        if !known {
            return Err("Unknown notification action".into());
        }
        if entry.snapshot.resident {
            entry.hide_popup();
            return Ok(false);
        }
        self.remove(id);
        self.save_history(None, &[id]);
        Ok(true)
    }

    fn save_history(&mut self, changed: Option<u32>, removed: &[u32]) {
        if let Some(history) = &mut self.history
            && let Err(error) = history.save(&self.entries, self.next_id, changed, removed)
        {
            eprintln!("Notification history save: {error}");
        }
    }

    /// Ends due popups. Transient notifications leave with them.
    fn expire(&mut self, now: Instant) -> Vec<u32> {
        let mut closed = Vec::new();
        for entry in &mut self.entries {
            if entry.deadline.is_some_and(|deadline| deadline <= now) {
                entry.hide_popup();
                if entry.snapshot.transient {
                    closed.push(entry.snapshot.id);
                }
            }
        }
        self.entries
            .retain(|entry| !closed.contains(&entry.snapshot.id));
        closed
    }

    fn set_hovered(&mut self, hovered: bool) {
        if self.hovered == hovered {
            return;
        }
        self.hovered = hovered;
        let now = Instant::now();
        for entry in &mut self.entries {
            if hovered {
                if let Some(deadline) = entry.deadline.take() {
                    entry.remaining = Some(deadline.saturating_duration_since(now));
                }
            } else if let Some(remaining) = entry.remaining.take() {
                entry.deadline = Some(now + remaining);
            }
        }
    }

    fn timeout(&self, requested_ms: i32) -> Option<Duration> {
        let millis = match requested_ms {
            0 => return None,
            value if value > 0 => value as u64,
            _ => u64::from(self.preferences.timeout_seconds.clamp(1, 600)) * 1000,
        };
        Some(Duration::from_millis(millis.max(2000)))
    }

    /// Recomputes Do Not Disturb and hides popups it now silences. Returns
    /// transient notifications that leave with their popup.
    fn refresh_quiet(&mut self, now: NaiveDateTime) -> Vec<u32> {
        let preferences = &self.preferences;
        let quiet = if preferences.do_not_disturb {
            Some("manual")
        } else if preferences.schedule && scheduled(preferences, now) {
            Some("schedule")
        } else if preferences.fullscreen && !self.fullscreen.is_empty() {
            Some("fullscreen")
        } else {
            None
        };
        let started = quiet.is_some() && self.quiet.is_none();
        self.quiet = quiet;
        if !started {
            return Vec::new();
        }
        let mut closed = Vec::new();
        for entry in &mut self.entries {
            if entry.snapshot.popup && !bypasses(&self.preferences, &entry.snapshot) {
                entry.hide_popup();
                if entry.snapshot.transient {
                    closed.push(entry.snapshot.id);
                }
            }
        }
        self.entries
            .retain(|entry| !closed.contains(&entry.snapshot.id));
        closed
    }

    fn claim(&mut self, output: String) -> bool {
        release_host(self);
        if !self.entries.iter().any(|entry| entry.snapshot.popup) {
            return false;
        }
        match &self.popup_host {
            Some(host) => *host == output,
            None => {
                self.popup_host = Some(output);
                true
            }
        }
    }

    fn next_deadline(&self) -> Option<Instant> {
        self.entries.iter().filter_map(|entry| entry.deadline).min()
    }
}

fn daemon() -> &'static Mutex<Daemon> {
    static DAEMON: OnceLock<Mutex<Daemon>> = OnceLock::new();
    DAEMON.get_or_init(|| Mutex::new(Daemon::new()))
}

fn updates() -> &'static watch::Sender<NotificationCenter> {
    static UPDATES: OnceLock<watch::Sender<NotificationCenter>> = OnceLock::new();
    UPDATES.get_or_init(|| watch::channel(Daemon::new().center()).0)
}

fn timers() -> &'static Notify {
    static TIMERS: OnceLock<Notify> = OnceLock::new();
    TIMERS.get_or_init(Notify::new)
}

fn publish(daemon: &mut Daemon) {
    release_host(daemon);
    updates().send_replace(daemon.center());
    timers().notify_one();
}

async fn emit(connection: &Option<zbus::Connection>, member: &str, body: (u32, Option<&str>, u32)) {
    let Some(connection) = connection else { return };
    let result = match body {
        (id, Some(action), _) => {
            connection
                .emit_signal(None::<&str>, PATH, NAME, member, &(id, action))
                .await
        }
        (id, None, reason) => {
            connection
                .emit_signal(None::<&str>, PATH, NAME, member, &(id, reason))
                .await
        }
    };
    if let Err(error) = result {
        eprintln!("Notification signal {member}: {error}");
    }
}

async fn closed(connection: Option<zbus::Connection>, ids: Vec<u32>, reason: u32) {
    for id in ids {
        emit(&connection, "NotificationClosed", (id, None, reason)).await;
    }
}

struct Server {
    ready: watch::Receiver<bool>,
}

impl Server {
    async fn wait_until_ready(&self) -> zbus::fdo::Result<()> {
        self.ready
            .clone()
            .wait_for(|ready| *ready)
            .await
            .map(|_| ())
            .map_err(|_| zbus::fdo::Error::Failed("Notification service startup failed".into()))
    }
}

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl Server {
    #[allow(clippy::too_many_arguments)]
    async fn notify(
        &self,
        app_name: String,
        replaces_id: u32,
        app_icon: String,
        summary: String,
        body: String,
        actions: Vec<String>,
        hints: HashMap<String, OwnedValue>,
        expire_timeout: i32,
    ) -> zbus::fdo::Result<u32> {
        self.wait_until_ready().await?;
        let mut daemon = daemon().lock().await;
        let urgency = hint_byte(&hints, "urgency")
            .filter(|value| *value <= 2)
            .unwrap_or(1);
        let (image_argb, image_width, image_height) = ["image-data", "image_data", "icon_data"]
            .iter()
            .find_map(|key| hints.get(*key).and_then(image_data))
            .unwrap_or_default();
        let (actions, default_action) = parse_actions(actions);
        let snapshot = NotificationSnapshot {
            id: 0,
            app_name,
            app_icon,
            desktop_entry: hint_string(&hints, "desktop-entry").unwrap_or_default(),
            summary,
            body: parse_body(&body),
            actions,
            default_action,
            urgency,
            received_unix_ms: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_or(0, |time| time.as_millis() as i64),
            image_argb,
            image_width,
            image_height,
            image_path: ["image-path", "image_path"]
                .iter()
                .find_map(|key| hint_string(&hints, key))
                .unwrap_or_default(),
            progress: hint_int(&hints, "value").map(|value| value.clamp(0, 100)),
            popup: false,
            popup_sequence: 0,
            transient: hint_bool(&hints, "transient"),
            resident: hint_bool(&hints, "resident"),
            category: hint_string(&hints, "category").unwrap_or_default(),
        };
        let mut dropped = daemon.refresh_quiet(Local::now().naive_local());
        let timeout = daemon.timeout(expire_timeout);
        let (index, is_new) = daemon.receive(snapshot, replaces_id, timeout);
        let id = daemon.entries[index].snapshot.id;
        // Updates such as progress stay silent.
        if is_new
            && daemon.entries[index].snapshot.popup
            && daemon.preferences.sounds
            && !hint_bool(&hints, "suppress-sound")
        {
            play_sound(
                hint_string(&hints, "sound-file"),
                hint_string(&hints, "sound-name"),
            );
        }
        // A transient notification that cannot pop up has nowhere to appear.
        if daemon.entries[index].snapshot.transient && !daemon.entries[index].snapshot.popup {
            dropped.push(id);
        }
        while daemon.entries.len() > HISTORY_LIMIT {
            dropped.push(daemon.entries.pop().unwrap().snapshot.id);
        }
        daemon
            .entries
            .retain(|entry| !dropped.contains(&entry.snapshot.id));
        daemon.save_history(Some(id), &dropped);
        publish(&mut daemon);
        let connection = daemon.connection.clone();
        drop(daemon);
        if !dropped.is_empty() {
            tokio::spawn(closed(connection, dropped, EXPIRED));
        }
        Ok(id)
    }

    async fn close_notification(&self, id: u32) -> zbus::fdo::Result<()> {
        self.wait_until_ready().await?;
        let mut daemon = daemon().lock().await;
        if daemon.remove(id) {
            daemon.save_history(None, &[id]);
            publish(&mut daemon);
            let connection = daemon.connection.clone();
            drop(daemon);
            tokio::spawn(closed(connection, vec![id], CLOSED));
        }
        Ok(())
    }

    fn get_capabilities(&self) -> Vec<&'static str> {
        vec![
            "actions",
            "sound",
            "body",
            "body-markup",
            "body-hyperlinks",
            "icon-static",
            "persistence",
        ]
    }

    fn get_server_information(&self) -> (&'static str, &'static str, &'static str, &'static str) {
        ("Remy'a Bar", "Remy'a", env!("CARGO_PKG_VERSION"), "1.2")
    }

    #[zbus(signal)]
    async fn notification_closed(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        id: u32,
        reason: u32,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn action_invoked(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        id: u32,
        action_key: &str,
    ) -> zbus::Result<()>;
}

/// Starts the D-Bus server and timer once for the process.
fn ensure_started() {
    static STARTED: OnceLock<()> = OnceLock::new();
    STARTED.get_or_init(|| {
        tokio::spawn(serve());
        tokio::spawn(expire_popups());
    });
}

async fn serve() {
    while !start_server(own_name).await {
        let _ = tokio::time::timeout(Duration::from_secs(5), server_retry().notified()).await;
    }
}

fn server_retry() -> &'static Notify {
    static RETRY: OnceLock<Notify> = OnceLock::new();
    RETRY.get_or_init(Notify::new)
}

pub(crate) fn retry() {
    ensure_started();
    server_retry().notify_one();
}

async fn start_server(claim: impl AsyncFnOnce(Server) -> Result<zbus::Connection, String>) -> bool {
    let (ready, server) = watch::channel(false);
    let result = tokio::time::timeout(Duration::from_secs(3), claim(Server { ready: server }))
        .await
        .unwrap_or_else(|_| Err("Notification D-Bus ownership timed out".into()));
    match result {
        Ok(connection) => {
            let history = tokio::task::spawn_blocking(history::open).await;
            let mut daemon = daemon().lock().await;
            match history {
                Ok(Ok((history, entries, next_id))) => {
                    daemon.history = Some(history);
                    daemon.entries = entries;
                    daemon.next_id = next_id;
                }
                Ok(Err(error)) => eprintln!("Notification history open: {error}"),
                Err(error) => eprintln!("Notification history worker: {error}"),
            }
            daemon.connection = Some(connection);
            daemon.error = None;
            publish(&mut daemon);
            // Calls can arrive as soon as the bus grants the name.
            ready.send_replace(true);
            true
        }
        Err(error) => {
            let mut daemon = daemon().lock().await;
            if daemon.error.as_deref() != Some(error.as_str()) {
                daemon.error = Some(error);
                publish(&mut daemon);
            }
            false
        }
    }
}

async fn own_name(server: Server) -> Result<zbus::Connection, String> {
    use zbus::fdo::{RequestNameFlags, RequestNameReply};
    let connection = zbus::Connection::session()
        .await
        .map_err(|e| e.to_string())?;
    connection
        .object_server()
        .at(PATH, server)
        .await
        .map_err(|e| e.to_string())?;
    let reply = connection
        .request_name_with_flags(NAME, RequestNameFlags::DoNotQueue.into())
        .await;
    match reply {
        Ok(RequestNameReply::PrimaryOwner | RequestNameReply::AlreadyOwner) => Ok(connection),
        Ok(_) | Err(zbus::Error::NameTaken) => Err("Another notification daemon is running".into()),
        Err(error) => Err(error.to_string()),
    }
}

async fn expire_popups() {
    loop {
        let (next_popup, next_schedule, next_retry) = {
            let daemon = daemon().lock().await;
            let now_instant = Instant::now();
            (
                daemon.next_deadline(),
                next_schedule_boundary(&daemon.preferences, Local::now().naive_local())
                    .map(|delay| now_instant + delay),
                daemon
                    .history
                    .as_ref()
                    .is_some_and(History::needs_retry)
                    .then(|| now_instant + Duration::from_secs(30)),
            )
        };
        let deadline = [next_popup, next_schedule, next_retry]
            .into_iter()
            .flatten()
            .min();
        let wake = timers().notified();
        if let Some(deadline) = deadline {
            let _ = tokio::time::timeout_at(deadline.into(), wake).await;
        } else {
            wake.await;
        }
        let mut daemon = daemon().lock().await;
        let before = daemon.center();
        let mut ended = daemon.refresh_quiet(Local::now().naive_local());
        ended.extend(daemon.expire(Instant::now()));
        if daemon.history.as_ref().is_some_and(History::needs_retry) {
            daemon.save_history(None, &[]);
        }
        release_host(&mut daemon);
        let after = daemon.center();
        if after != before {
            updates().send_replace(after);
        }
        let connection = daemon.connection.clone();
        drop(daemon);
        closed(connection, ended, EXPIRED).await;
    }
}

fn release_host(daemon: &mut Daemon) {
    if !daemon.entries.iter().any(|entry| entry.snapshot.popup) {
        daemon.popup_host = None;
        daemon.hovered = false;
    }
}

/// The first output to claim a non-empty stack hosts it until it empties.
pub(crate) async fn claim_popups(output: String) -> bool {
    let mut daemon = daemon().lock().await;
    let unclaimed = daemon.popup_host.is_none();
    let claimed = daemon.claim(output);
    if claimed && unclaimed {
        publish(&mut daemon);
    }
    claimed
}

pub(crate) async fn subscribe(sink: StreamSink<NotificationCenter>) {
    ensure_started();
    let mut changes = updates().subscribe();
    loop {
        let center = changes.borrow_and_update().clone();
        if sink.add(center).is_err() || changes.changed().await.is_err() {
            return;
        }
    }
}

pub(crate) async fn configure(preferences: NotificationPreferences) {
    let mut daemon = daemon().lock().await;
    daemon.preferences = preferences;
    daemon.preferences_loaded = true;
    let ended = daemon.refresh_quiet(Local::now().naive_local());
    publish(&mut daemon);
    timers().notify_one();
    let connection = daemon.connection.clone();
    drop(daemon);
    if tokio::time::timeout(Duration::from_secs(2), closed(connection, ended, EXPIRED))
        .await
        .is_err()
    {
        eprintln!("Timed out sending notification close signals after settings change");
    }
}

pub(crate) async fn fullscreen(output: String, fullscreen: bool) {
    let mut daemon = daemon().lock().await;
    let changed = if fullscreen {
        daemon.fullscreen.insert(output)
    } else {
        daemon.fullscreen.remove(&output)
    };
    if !changed {
        return;
    }
    let ended = daemon.refresh_quiet(Local::now().naive_local());
    publish(&mut daemon);
    timers().notify_one();
    let connection = daemon.connection.clone();
    drop(daemon);
    closed(connection, ended, EXPIRED).await;
}

pub(crate) async fn hover(hovered: bool) {
    let mut daemon = daemon().lock().await;
    let hovered = hovered && daemon.entries.iter().any(|entry| entry.snapshot.popup);
    daemon.set_hovered(hovered);
    timers().notify_one();
}

pub(crate) async fn dismiss(id: Option<u32>) -> Result<(), String> {
    dismiss_matching(id, None, None).await
}

pub(crate) async fn clear(urgency: Option<u8>, group: Option<&str>) -> Result<(), String> {
    dismiss_matching(None, urgency, group).await
}

async fn dismiss_matching(
    id: Option<u32>,
    urgency: Option<u8>,
    group: Option<&str>,
) -> Result<(), String> {
    let mut daemon = daemon().lock().await;
    let clear_critical = daemon.preferences.clear_critical || urgency.is_some() || group.is_some();
    let removed = remove_matching(&mut daemon.entries, id, urgency, group, clear_critical);
    if removed.is_empty() {
        return if id.is_some() {
            Err("Notification is gone".into())
        } else {
            Ok(())
        };
    }
    daemon.save_history(None, &removed);
    publish(&mut daemon);
    let connection = daemon.connection.clone();
    drop(daemon);
    closed(connection, removed, DISMISSED).await;
    Ok(())
}

fn remove_matching(
    entries: &mut Vec<Entry>,
    id: Option<u32>,
    urgency: Option<u8>,
    group: Option<&str>,
    clear_critical: bool,
) -> Vec<u32> {
    let mut removed = Vec::new();
    entries.retain(|entry| {
        let item = &entry.snapshot;
        let matches = match id {
            Some(id) => id == item.id,
            None => {
                !item.resident
                    && !item.transient
                    && (clear_critical || item.urgency != 2)
                    && urgency.is_none_or(|urgency| urgency == item.urgency)
                    && group.is_none_or(|group| {
                        group
                            == if item.desktop_entry.is_empty() {
                                item.app_name.as_str()
                            } else {
                                item.desktop_entry.as_str()
                            }
                    })
            }
        };
        if matches {
            removed.push(item.id);
        }
        !matches
    });
    removed
}

/// Invokes an action; non-resident notifications close afterwards.
pub(crate) async fn invoke(id: u32, action: &str) -> Result<(), String> {
    let mut daemon = daemon().lock().await;
    let dismissed = daemon.apply_action(id, action)?;
    publish(&mut daemon);
    let connection = daemon.connection.clone();
    drop(daemon);
    emit(&connection, "ActionInvoked", (id, Some(action), 0)).await;
    if dismissed {
        closed(connection, vec![id], DISMISSED).await;
    }
    Ok(())
}

#[cfg(test)]
mod tests;
