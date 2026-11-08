//! Process-wide `org.freedesktop.Notifications` server shared by every output.
use crate::api::{
    NotificationAction, NotificationCenter, NotificationPreferences, NotificationSnapshot,
    NotificationText,
};
use crate::frb_generated::StreamSink;
use chrono::{Datelike, Local, NaiveDateTime, Timelike};
use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{Mutex, Notify, watch};
use zbus::zvariant::{OwnedValue, Value};

const NAME: &str = "org.freedesktop.Notifications";
const PATH: &str = "/org/freedesktop/Notifications";
const HISTORY_LIMIT: usize = 200;
const IMAGE_LIMIT: u32 = 128;

const EXPIRED: u32 = 1;
const DISMISSED: u32 = 2;
const CLOSED: u32 = 3;

struct Entry {
    snapshot: NotificationSnapshot,
    timeout: Option<Duration>,
    deadline: Option<Instant>,
    remaining: Option<Duration>,
}

struct Daemon {
    entries: Vec<Entry>,
    next_id: u32,
    preferences: NotificationPreferences,
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
            preferences: NotificationPreferences {
                do_not_disturb: false,
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
            quiet_reason: self.quiet.unwrap_or_default().into(),
            popup_host: self.popup_host.clone(),
            error: self.error.clone(),
        }
    }

    fn start_popup(&mut self, index: usize) {
        let entry = &mut self.entries[index];
        let critical = entry.snapshot.urgency == 2;
        entry.snapshot.popup = self.quiet.is_none() || bypasses(&self.preferences, &entry.snapshot);
        entry.remaining = None;
        entry.deadline = None;
        // `timeout` is None for senders that ask never to expire.
        if entry.snapshot.popup
            && !critical
            && let Some(timeout) = entry.timeout
        {
            if self.hovered {
                entry.remaining = Some(timeout);
            } else {
                entry.deadline = Some(Instant::now() + timeout);
            }
        }
    }

    fn remove(&mut self, id: u32) -> bool {
        let before = self.entries.len();
        self.entries.retain(|entry| entry.snapshot.id != id);
        self.entries.len() != before
    }

    /// Ends due popups. Transient notifications leave with them.
    fn expire(&mut self, now: Instant) -> Vec<u32> {
        let mut closed = Vec::new();
        for entry in &mut self.entries {
            if entry.deadline.is_some_and(|deadline| deadline <= now) {
                entry.deadline = None;
                entry.snapshot.popup = false;
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

    fn default_timeout(&self) -> Duration {
        Duration::from_secs(u64::from(self.preferences.timeout_seconds.clamp(1, 600)))
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
                entry.snapshot.popup = false;
                entry.deadline = None;
                entry.remaining = None;
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

/// Critical, call and priority app notifications break through Do Not Disturb.
fn bypasses(preferences: &NotificationPreferences, snapshot: &NotificationSnapshot) -> bool {
    snapshot.urgency == 2
        || preferences.priority_calls
            && matches!(snapshot.category.as_str(), "call" | "call.incoming")
        || preferences.priority_apps.iter().any(|app| {
            (!snapshot.desktop_entry.is_empty()
                && app.id.eq_ignore_ascii_case(&snapshot.desktop_entry))
                || (!snapshot.app_name.is_empty()
                    && app.name.eq_ignore_ascii_case(&snapshot.app_name))
        })
}

/// Whether the schedule covers `now`; a period crossing midnight belongs to
/// the day it starts. Equal start and end times mean no period.
fn scheduled(preferences: &NotificationPreferences, now: NaiveDateTime) -> bool {
    let (start, end) = (
        preferences.schedule_start_minutes,
        preferences.schedule_end_minutes,
    );
    let minute = now.hour() * 60 + now.minute();
    let today = now.weekday().number_from_monday();
    let yesterday = now.weekday().pred().number_from_monday();
    let starts = |day: u32| preferences.schedule_days.contains(&day);
    if start < end {
        starts(today) && (start..end).contains(&minute)
    } else if start > end {
        starts(today) && minute >= start || starts(yesterday) && minute < end
    } else {
        false
    }
}

/// Plays the requested sound or the theme's message sound through libcanberra.
fn play_sound(file: Option<String>, name: Option<String>) {
    let mut command = tokio::process::Command::new("canberra-gtk-play");
    match (file, name) {
        (Some(file), _) => command.args(["-f", &file]),
        (None, Some(name)) => command.args(["-i", &name]),
        (None, None) => command.args(["-i", "message-new-instant"]),
    };
    command.arg("-d").arg("Notification");
    match command.kill_on_drop(false).spawn() {
        Ok(mut child) => {
            tokio::spawn(async move {
                let _ = child.wait().await;
            });
        }
        Err(error) => eprintln!("Notification sound: {error}"),
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

struct Server;

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
    ) -> u32 {
        let mut daemon = daemon().lock().await;
        let urgency = hint_byte(&hints, "urgency")
            .filter(|value| *value <= 2)
            .unwrap_or(1);
        let (image_argb, image_width, image_height) = ["image-data", "image_data", "icon_data"]
            .iter()
            .find_map(|key| hints.get(*key).and_then(image_data))
            .unwrap_or_default();
        let (actions, default_action) = parse_actions(actions);
        let mut snapshot = NotificationSnapshot {
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
            transient: hint_bool(&hints, "transient"),
            resident: hint_bool(&hints, "resident"),
            category: hint_string(&hints, "category").unwrap_or_default(),
        };
        let mut dropped = daemon.refresh_quiet(Local::now().naive_local());
        let timeout = match expire_timeout {
            0 => None,
            value if value > 0 => Some(Duration::from_millis(value as u64)),
            _ => Some(daemon.default_timeout()),
        };
        let replaced = replaces_id != 0
            && daemon
                .entries
                .iter()
                .any(|entry| entry.snapshot.id == replaces_id);
        // Replacement updates in place instead of reordering the history.
        let index = match daemon
            .entries
            .iter()
            .position(|entry| replaces_id != 0 && entry.snapshot.id == replaces_id)
        {
            Some(index) => {
                snapshot.id = replaces_id;
                daemon.entries[index].snapshot = snapshot;
                daemon.entries[index].timeout = timeout;
                index
            }
            None => {
                snapshot.id = daemon.allocate_id();
                let entry = Entry {
                    snapshot,
                    timeout,
                    deadline: None,
                    remaining: None,
                };
                daemon.entries.insert(0, entry);
                0
            }
        };
        daemon.start_popup(index);
        let id = daemon.entries[index].snapshot.id;
        // Updates such as progress stay silent.
        if !replaced
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
        publish(&mut daemon);
        let connection = daemon.connection.clone();
        drop(daemon);
        if !dropped.is_empty() {
            tokio::spawn(closed(connection, dropped, EXPIRED));
        }
        id
    }

    async fn close_notification(&self, id: u32) {
        let mut daemon = daemon().lock().await;
        if daemon.remove(id) {
            publish(&mut daemon);
            let connection = daemon.connection.clone();
            drop(daemon);
            tokio::spawn(closed(connection, vec![id], CLOSED));
        }
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

fn hint_string(hints: &HashMap<String, OwnedValue>, key: &str) -> Option<String> {
    hints
        .get(key)
        .and_then(|value| <&str>::try_from(value).ok())
        .map(str::to_owned)
        .filter(|value| !value.is_empty() && value.len() <= 4096)
}

fn hint_bool(hints: &HashMap<String, OwnedValue>, key: &str) -> bool {
    hints.get(key).is_some_and(|value| match &**value {
        Value::Bool(value) => *value,
        Value::U8(value) => *value != 0,
        Value::I32(value) => *value != 0,
        _ => false,
    })
}

fn hint_byte(hints: &HashMap<String, OwnedValue>, key: &str) -> Option<u8> {
    hint_int(hints, key).and_then(|value| u8::try_from(value).ok())
}

fn hint_int(hints: &HashMap<String, OwnedValue>, key: &str) -> Option<i32> {
    match &**hints.get(key)? {
        Value::U8(value) => Some(i32::from(*value)),
        Value::I16(value) => Some(i32::from(*value)),
        Value::U16(value) => Some(i32::from(*value)),
        Value::I32(value) => Some(*value),
        Value::U32(value) => i32::try_from(*value).ok(),
        Value::I64(value) => i32::try_from(*value).ok(),
        Value::U64(value) => i32::try_from(*value).ok(),
        _ => None,
    }
}

fn parse_actions(flat: Vec<String>) -> (Vec<NotificationAction>, bool) {
    let mut default_action = false;
    let mut actions = Vec::new();
    for pair in flat.as_chunks::<2>().0 {
        if pair[0] == "default" {
            default_action = true;
        } else if !pair[0].is_empty() {
            actions.push(NotificationAction {
                key: pair[0].clone(),
                label: pair[1].clone(),
            });
        }
    }
    (actions, default_action)
}

/// Decodes `(iiibiiay)` image hints into tray-compatible ARGB, at most 128 px.
fn image_data(value: &OwnedValue) -> Option<(Vec<u8>, u32, u32)> {
    let Value::Structure(structure) = &**value else {
        return None;
    };
    let fields = structure.fields();
    if fields.len() != 7 {
        return None;
    }
    let int = |index: usize| match &fields[index] {
        Value::I32(value) => Some(*value),
        _ => None,
    };
    let (width, height, rowstride) = (int(0)?, int(1)?, int(2)?);
    let Value::Bool(has_alpha) = fields[3] else {
        return None;
    };
    let (bits, channels) = (int(4)?, int(5)?);
    let Value::Array(array) = &fields[6] else {
        return None;
    };
    let data: Vec<u8> = array
        .iter()
        .filter_map(|byte| u8::try_from(byte).ok())
        .collect();
    decode_pixels(width, height, rowstride, has_alpha, bits, channels, &data)
}

fn decode_pixels(
    width: i32,
    height: i32,
    rowstride: i32,
    has_alpha: bool,
    bits: i32,
    channels: i32,
    data: &[u8],
) -> Option<(Vec<u8>, u32, u32)> {
    if !(1..=4096).contains(&width)
        || !(1..=4096).contains(&height)
        || bits != 8
        || channels != if has_alpha { 4 } else { 3 }
        || rowstride < width * channels
    {
        return None;
    }
    let (width, height, rowstride, channels) = (
        width as usize,
        height as usize,
        rowstride as usize,
        channels as usize,
    );
    if data.len() < rowstride * (height - 1) + width * channels {
        return None;
    }
    let scale = (width.max(height) as f64 / f64::from(IMAGE_LIMIT)).max(1.0);
    let target_width = ((width as f64 / scale).round() as usize).max(1);
    let target_height = ((height as f64 / scale).round() as usize).max(1);
    let mut argb = Vec::with_capacity(target_width * target_height * 4);
    for y in 0..target_height {
        let source_y = ((y as f64 + 0.5) * scale) as usize;
        for x in 0..target_width {
            let source_x = ((x as f64 + 0.5) * scale) as usize;
            let offset = source_y.min(height - 1) * rowstride + source_x.min(width - 1) * channels;
            let pixel = &data[offset..offset + channels];
            argb.extend_from_slice(&[
                if has_alpha { pixel[3] } else { 255 },
                pixel[0],
                pixel[1],
                pixel[2],
            ]);
        }
    }
    Some((argb, target_width as u32, target_height as u32))
}

/// Keeps `<b> <i> <u> <a href>` runs; malformed markup falls back to the raw text.
fn parse_body(body: &str) -> Vec<NotificationText> {
    parse_markup(body).unwrap_or_else(|| {
        if body.is_empty() {
            Vec::new()
        } else {
            vec![run(body.to_owned(), [false; 3], String::new())]
        }
    })
}

fn run(text: String, style: [bool; 3], href: String) -> NotificationText {
    NotificationText {
        text,
        bold: style[0],
        italic: style[1],
        underline: style[2],
        href,
    }
}

fn parse_markup(body: &str) -> Option<Vec<NotificationText>> {
    let mut runs: Vec<NotificationText> = Vec::new();
    let mut open: Vec<String> = Vec::new();
    let mut style = [false; 3];
    let mut href = String::new();
    let mut text = String::new();
    let mut rest = body;
    let mut flush = |text: &mut String, style: [bool; 3], href: &str| {
        if text.is_empty() {
            return;
        }
        match runs.last_mut() {
            Some(last)
                if [last.bold, last.italic, last.underline] == style && last.href == href =>
            {
                last.text.push_str(text)
            }
            _ => runs.push(run(text.clone(), style, href.to_owned())),
        }
        text.clear();
    };
    while let Some(start) = rest.find(['<', '&']) {
        text.push_str(&rest[..start]);
        rest = &rest[start..];
        if rest.starts_with('&') {
            let end = rest.find(';').filter(|end| *end <= 10)?;
            text.push(entity(&rest[1..end])?);
            rest = &rest[end + 1..];
            continue;
        }
        let end = rest.find('>')?;
        let tag = rest[1..end].trim();
        rest = &rest[end + 1..];
        let closing = tag.strip_prefix('/');
        let name = closing
            .unwrap_or(tag)
            .split(|c: char| c.is_whitespace() || c == '/')
            .next()?
            .to_ascii_lowercase();
        if name.is_empty() || !name.chars().all(|c| c.is_ascii_alphanumeric()) {
            return None;
        }
        if matches!(name.as_str(), "br" | "img") {
            if name == "br" {
                text.push('\n');
            }
            continue;
        }
        flush(&mut text, style, &href);
        if closing.is_some() {
            if open.pop()? != name {
                return None;
            }
        } else if !tag.ends_with('/') {
            open.push(name.clone());
            if name == "a" {
                href = link(tag).unwrap_or_default();
            }
        }
        let active = |tag: &str| open.iter().any(|open| open == tag);
        style = [active("b"), active("i"), active("u")];
        if !active("a") {
            href.clear();
        }
    }
    if !open.is_empty() {
        return None;
    }
    text.push_str(rest);
    flush(&mut text, style, &href);
    Some(runs)
}

fn entity(name: &str) -> Option<char> {
    match name {
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "quot" => Some('"'),
        "apos" => Some('\''),
        _ => {
            let number = name.strip_prefix('#')?;
            let code = match number.strip_prefix(['x', 'X']) {
                Some(hex) => u32::from_str_radix(hex, 16).ok()?,
                None => number.parse().ok()?,
            };
            char::from_u32(code)
        }
    }
}

/// Only web and mail links open from a notification body.
fn link(tag: &str) -> Option<String> {
    let start = tag.find("href=")? + 5;
    let value = &tag[start..];
    let quote = value.chars().next().filter(|c| *c == '"' || *c == '\'')?;
    let value = &value[1..];
    let href = &value[..value.find(quote)?];
    let href = href.replace("&amp;", "&");
    ["https://", "http://", "mailto:"]
        .iter()
        .any(|scheme| href.to_ascii_lowercase().starts_with(scheme))
        .then_some(href)
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
    loop {
        match own_name().await {
            Ok(connection) => {
                let mut daemon = daemon().lock().await;
                daemon.connection = Some(connection);
                daemon.error = None;
                publish(&mut daemon);
                return;
            }
            Err(error) => {
                let mut daemon = daemon().lock().await;
                if daemon.error.as_deref() != Some(error.as_str()) {
                    daemon.error = Some(error);
                    publish(&mut daemon);
                }
            }
        }
        // Another daemon may release the name later.
        tokio::time::sleep(Duration::from_secs(5)).await;
    }
}

async fn own_name() -> Result<zbus::Connection, String> {
    use zbus::fdo::{RequestNameFlags, RequestNameReply};
    let connection = zbus::Connection::session()
        .await
        .map_err(|e| e.to_string())?;
    connection
        .object_server()
        .at(PATH, Server)
        .await
        .map_err(|e| e.to_string())?;
    let reply = connection
        .request_name_with_flags(NAME, RequestNameFlags::DoNotQueue.into())
        .await;
    match reply {
        Ok(RequestNameReply::PrimaryOwner | RequestNameReply::AlreadyOwner) => Ok(connection),
        Ok(_) | Err(zbus::Error::NameTaken) => {
            Err("Another notification service is running".into())
        }
        Err(error) => Err(error.to_string()),
    }
}

async fn expire_popups() {
    loop {
        let next = daemon().lock().await.next_deadline();
        // The schedule is checked every 30 seconds even without popups.
        let tick = Instant::now() + Duration::from_secs(30);
        let wake = timers().notified();
        let _ =
            tokio::time::timeout_at(next.map_or(tick, |next| next.min(tick)).into(), wake).await;
        let mut daemon = daemon().lock().await;
        let before = daemon.center();
        let mut ended = daemon.refresh_quiet(Local::now().naive_local());
        ended.extend(daemon.expire(Instant::now()));
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
    let ended = daemon.refresh_quiet(Local::now().naive_local());
    publish(&mut daemon);
    let connection = daemon.connection.clone();
    drop(daemon);
    closed(connection, ended, EXPIRED).await;
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
    let connection = daemon.connection.clone();
    drop(daemon);
    closed(connection, ended, EXPIRED).await;
}

pub(crate) async fn hover(hovered: bool) {
    let mut daemon = daemon().lock().await;
    daemon.set_hovered(hovered);
    timers().notify_one();
}

pub(crate) async fn dismiss(id: Option<u32>) -> Result<(), String> {
    let mut daemon = daemon().lock().await;
    let ids: Vec<u32> = match id {
        Some(id) => vec![id],
        None => daemon
            .entries
            .iter()
            .map(|entry| entry.snapshot.id)
            .collect(),
    };
    let removed: Vec<u32> = ids.into_iter().filter(|id| daemon.remove(*id)).collect();
    if removed.is_empty() && id.is_some() {
        return Err("Notification is gone".into());
    }
    publish(&mut daemon);
    let connection = daemon.connection.clone();
    drop(daemon);
    closed(connection, removed, DISMISSED).await;
    Ok(())
}

/// Invokes an action; non-resident notifications close afterwards.
pub(crate) async fn invoke(id: u32, action: &str) -> Result<(), String> {
    let mut daemon = daemon().lock().await;
    let entry = daemon
        .entries
        .iter()
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
    let resident = entry.snapshot.resident;
    if !resident {
        daemon.remove(id);
        publish(&mut daemon);
    }
    let connection = daemon.connection.clone();
    drop(daemon);
    emit(&connection, "ActionInvoked", (id, Some(action), 0)).await;
    if !resident {
        closed(connection, vec![id], DISMISSED).await;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(runs: &[NotificationText]) -> String {
        runs.iter().map(|run| run.text.as_str()).collect()
    }

    #[test]
    fn markup_keeps_supported_tags_and_safe_links() {
        let runs = parse_body(
            "Hi <b>bold <i>both</i></b> &amp; <a href=\"https://x.test/?a=1&amp;b\">link</a><br/>end",
        );
        assert_eq!(text(&runs), "Hi bold both & link\nend");
        assert!(
            runs.iter()
                .any(|run| run.bold && run.italic && run.text == "both")
        );
        assert_eq!(
            runs.iter().find(|run| run.text == "link").unwrap().href,
            "https://x.test/?a=1&b"
        );
        let unsafe_link = parse_body("<a href='file:///etc/passwd'>x</a>");
        assert_eq!(unsafe_link[0].href, "");
    }

    #[test]
    fn malformed_markup_falls_back_to_plain_text() {
        for body in ["a < b", "<b>open", "<b>x</i>", "AT&T rocks"] {
            assert_eq!(text(&parse_body(body)), body);
        }
        assert!(parse_body("").is_empty());
    }

    #[test]
    fn images_honor_rowstride_and_downscale() {
        // 2x1 RGB with one padding byte per row.
        let (argb, width, height) =
            decode_pixels(2, 1, 7, false, 8, 3, &[1, 2, 3, 4, 5, 6, 0]).unwrap();
        assert_eq!((width, height), (2, 1));
        assert_eq!(argb, vec![255, 1, 2, 3, 255, 4, 5, 6]);
        assert!(decode_pixels(2, 2, 7, false, 8, 3, &[0; 9]).is_none());
        assert!(decode_pixels(2, 1, 8, true, 8, 3, &[0; 8]).is_none());
        let large = vec![9; 512 * 256 * 4];
        let (_, width, height) = decode_pixels(512, 256, 2048, true, 8, 4, &large).unwrap();
        assert_eq!((width, height), (128, 64));
    }

    #[test]
    fn actions_split_default_and_ignore_odd_tail() {
        let (actions, default_action) = parse_actions(
            ["default", "", "reply", "Reply", "dangling"]
                .map(String::from)
                .to_vec(),
        );
        assert!(default_action);
        assert_eq!(actions.len(), 1);
        assert_eq!(actions[0].label, "Reply");
    }

    fn entry(id: u32, urgency: u8, transient: bool) -> Entry {
        Entry {
            snapshot: NotificationSnapshot {
                id,
                app_name: String::new(),
                app_icon: String::new(),
                desktop_entry: String::new(),
                summary: String::new(),
                body: Vec::new(),
                actions: Vec::new(),
                default_action: false,
                urgency,
                received_unix_ms: 0,
                image_argb: Vec::new(),
                image_width: 0,
                image_height: 0,
                image_path: String::new(),
                progress: None,
                popup: false,
                transient,
                resident: false,
                category: String::new(),
            },
            timeout: Some(Duration::from_secs(1)),
            deadline: None,
            remaining: None,
        }
    }

    #[test]
    fn popups_expire_pause_and_respect_do_not_disturb() {
        let mut daemon = Daemon::new();
        daemon.entries = vec![entry(1, 1, false), entry(2, 1, true), entry(3, 2, false)];
        for index in 0..3 {
            daemon.start_popup(index);
        }
        assert!(daemon.entries.iter().all(|entry| entry.snapshot.popup));
        assert!(
            daemon.entries[2].deadline.is_none(),
            "critical never expires"
        );
        daemon.set_hovered(true);
        assert!(
            daemon
                .expire(Instant::now() + Duration::from_secs(5))
                .is_empty()
        );
        daemon.set_hovered(false);
        assert_eq!(
            daemon.expire(Instant::now() + Duration::from_secs(5)),
            vec![2]
        );
        assert_eq!(daemon.entries.len(), 2, "transient leaves history");
        assert!(!daemon.entries[0].snapshot.popup);

        daemon.preferences.do_not_disturb = true;
        daemon.refresh_quiet(now());
        daemon.start_popup(0);
        daemon.start_popup(1);
        assert!(!daemon.entries[0].snapshot.popup);
        assert!(daemon.entries[1].snapshot.popup, "critical bypasses DND");
    }

    #[test]
    fn one_output_hosts_popups_until_they_end() {
        let mut daemon = Daemon::new();
        assert!(!daemon.claim("DP-1".into()), "nothing to host");
        daemon.entries.push(entry(1, 1, false));
        daemon.start_popup(0);
        assert!(daemon.claim("DP-1".into()));
        assert!(!daemon.claim("DP-3".into()));
        assert!(daemon.claim("DP-1".into()));
        daemon.expire(Instant::now() + Duration::from_secs(5));
        release_host(&mut daemon);
        daemon.start_popup(0);
        assert!(
            daemon.claim("DP-3".into()),
            "an emptied stack frees the host"
        );
    }

    fn now() -> NaiveDateTime {
        at("2026-11-09 12:00") // A Monday.
    }

    fn at(time: &str) -> NaiveDateTime {
        NaiveDateTime::parse_from_str(time, "%Y-%m-%d %H:%M").unwrap()
    }

    #[test]
    fn schedules_cross_midnight_from_their_start_day() {
        let mut preferences = Daemon::new().preferences;
        preferences.schedule_days = (1..=5).collect(); // Weekdays.
        assert!(
            scheduled(&preferences, at("2026-11-09 23:00")),
            "Monday night"
        );
        assert!(
            scheduled(&preferences, at("2026-11-10 06:59")),
            "Monday's period"
        );
        assert!(!scheduled(&preferences, at("2026-11-10 07:00")));
        assert!(!scheduled(&preferences, at("2026-11-14 23:00")), "Saturday");
        assert!(
            scheduled(&preferences, at("2026-11-14 06:00")),
            "Friday's period"
        );
        assert!(
            !scheduled(&preferences, at("2026-11-16 06:00")),
            "Sunday's period"
        );
        preferences.schedule_start_minutes = 9 * 60;
        preferences.schedule_end_minutes = 17 * 60;
        assert!(scheduled(&preferences, at("2026-11-09 12:00")));
        assert!(!scheduled(&preferences, at("2026-11-09 17:00")));
        preferences.schedule_end_minutes = 9 * 60;
        assert!(
            !scheduled(&preferences, at("2026-11-09 09:00")),
            "empty period"
        );
    }

    #[test]
    fn quiet_reasons_and_priority_bypass() {
        let mut daemon = Daemon::new();
        daemon.preferences.fullscreen = true;
        daemon.fullscreen.insert("DP-1".into());
        let mut call = entry(1, 1, false);
        call.snapshot.category = "call.incoming".into();
        let mut chat = entry(2, 1, false);
        chat.snapshot.desktop_entry = "org.telegram.desktop".into();
        let mut named = entry(3, 1, false);
        named.snapshot.app_name = "Signal".into();
        daemon.entries = vec![call, chat, named, entry(4, 1, false)];
        for index in 0..4 {
            daemon.start_popup(index);
        }
        daemon.refresh_quiet(now());
        assert_eq!(daemon.quiet, Some("fullscreen"));
        daemon.preferences.priority_apps = vec![
            crate::api::NotificationPriorityApp {
                id: "ORG.TELEGRAM.DESKTOP".into(),
                name: "Telegram".into(),
            },
            crate::api::NotificationPriorityApp {
                id: "org.signal.Signal".into(),
                name: "signal".into(),
            },
        ];
        for index in 0..4 {
            daemon.start_popup(index);
        }
        let shown: Vec<_> = daemon
            .entries
            .iter()
            .map(|entry| entry.snapshot.popup)
            .collect();
        assert_eq!(shown, [true, true, true, false]);
        daemon.preferences.priority_calls = false;
        daemon.start_popup(0);
        assert!(!daemon.entries[0].snapshot.popup);
        daemon.fullscreen.clear();
        daemon.refresh_quiet(now());
        assert_eq!(daemon.quiet, None);
        daemon.preferences.do_not_disturb = true;
        daemon.preferences.schedule = true;
        daemon.preferences.schedule_start_minutes = 11 * 60;
        daemon.refresh_quiet(now());
        assert_eq!(daemon.quiet, Some("manual"), "manual wins over schedule");
    }

    #[test]
    fn zero_timeout_never_expires() {
        let mut daemon = Daemon::new();
        let mut never = entry(1, 1, false);
        never.timeout = None;
        daemon.entries.push(never);
        daemon.start_popup(0);
        assert!(daemon.entries[0].snapshot.popup);
        assert!(daemon.entries[0].deadline.is_none());
    }

    #[test]
    fn ids_start_at_one_and_skip_zero_and_live_ids() {
        let mut daemon = Daemon::new();
        assert_eq!(daemon.allocate_id(), 1);
        daemon.entries.push(entry(2, 1, false));
        assert_eq!(daemon.allocate_id(), 3);
        daemon.next_id = u32::MAX;
        assert_eq!(daemon.allocate_id(), u32::MAX);
        assert_eq!(daemon.allocate_id(), 1);
    }
}
