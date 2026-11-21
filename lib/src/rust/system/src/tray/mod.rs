mod menu;
#[cfg(test)]
mod tests;
mod watcher;

use crate::api::TrayItem;
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::for_generated::futures::{FutureExt, StreamExt, stream};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::OnceLock;
use std::time::Duration;
use watcher::Watcher;
use zbus::zvariant::OwnedValue;

pub(crate) use menu::{menu, menu_action};

const WATCHER: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";
const ITEM: &str = "org.kde.StatusNotifierItem";
const ITEM_SIGNALS: &[&str] = &[
    "NewTitle",
    "NewIcon",
    "NewAttentionIcon",
    "NewOverlayIcon",
    "NewToolTip",
    "NewStatus",
    "NewMenu",
];
type Properties = HashMap<String, OwnedValue>;

struct Host {
    connection: zbus::Connection,
    watcher: Watcher,
    registered_with: tokio::sync::Mutex<Option<String>>,
}

async fn host() -> Result<&'static Host, String> {
    static HOST: OnceLock<tokio::sync::OnceCell<Host>> = OnceLock::new();
    HOST.get_or_init(Default::default)
        .get_or_try_init(|| async {
            let connection = zbus::Connection::session()
                .await
                .map_err(|e| e.to_string())?;
            let watcher = Watcher::default();
            connection
                .object_server()
                .at(WATCHER_PATH, watcher.clone())
                .await
                .map_err(|e| e.to_string())?;
            Ok(Host {
                connection,
                watcher,
                registered_with: Default::default(),
            })
        })
        .await
}

fn target(id: &str) -> Result<(&str, &str), String> {
    let split = id.find('/').ok_or("Invalid tray identifier")?;
    let (name, path) = id.split_at(split);
    zbus::names::BusName::try_from(name).map_err(|e| e.to_string())?;
    zbus::zvariant::ObjectPath::try_from(path).map_err(|e| e.to_string())?;
    Ok((name, path))
}

fn string(values: &Properties, key: &str) -> String {
    values
        .get(key)
        .and_then(|v| <&str>::try_from(v).ok())
        .unwrap_or_default()
        .into()
}

fn boolean(values: &Properties, key: &str, default: bool) -> bool {
    values
        .get(key)
        .and_then(|v| bool::try_from(v).ok())
        .unwrap_or(default)
}

async fn properties_for_target(
    connection: &zbus::Connection,
    name: &str,
    path: &str,
) -> Result<Properties, String> {
    let proxy = zbus::Proxy::new(connection, name, path, "org.freedesktop.DBus.Properties")
        .await
        .map_err(|e| e.to_string())?;
    proxy
        .call("GetAll", &(ITEM,))
        .await
        .map_err(|e| e.to_string())
}

async fn properties(connection: &zbus::Connection, id: &str) -> Result<Properties, String> {
    let (name, path) = target(id)?;
    properties_for_target(connection, name, path).await
}

fn pixmap(values: &Properties, key: &str) -> (u32, u32, Vec<u8>) {
    let pixels = values
        .get(key)
        .and_then(|v| v.try_clone().ok())
        .and_then(|v| Vec::<(i32, i32, Vec<u8>)>::try_from(v).ok())
        .unwrap_or_default();
    pixels
        .into_iter()
        .filter(|(w, h, p)| {
            *w > 0 && *h > 0 && *w <= 512 && *h <= 512 && p.len() == *w as usize * *h as usize * 4
        })
        .min_by_key(|(w, h, _)| {
            let size = (*w).min(*h);
            (size < 64, (size - 64).abs())
        })
        .map(|(w, h, p)| (w as u32, h as u32, p))
        .unwrap_or_default()
}

fn normalize_id(id: String) -> String {
    if id.contains('/') {
        id
    } else {
        format!("{id}/StatusNotifierItem")
    }
}

async fn registered_ids(host: &Host) -> Result<Vec<String>, String> {
    let proxy = zbus::Proxy::new(&host.connection, WATCHER, WATCHER_PATH, WATCHER)
        .await
        .map_err(|e| e.to_string())?;
    let ids: Vec<String> = proxy
        .get_property("RegisteredStatusNotifierItems")
        .await
        .map_err(|e| e.to_string())?;
    Ok(ids.into_iter().map(normalize_id).collect())
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct TrackedEntry {
    bus_name: String,
    owner: String,
    path: String,
    item: Option<TrayItem>,
}

#[derive(Default, Debug)]
struct ItemTracker {
    entries: BTreeMap<String, TrackedEntry>,
}

impl ItemTracker {
    fn upsert(&mut self, id: String, entry: TrackedEntry) {
        self.entries.insert(id, entry);
    }

    fn retain_ids(&mut self, ids: &BTreeSet<String>) {
        self.entries.retain(|id, _| ids.contains(id));
    }

    fn contains(&self, id: &str) -> bool {
        self.entries.contains_key(id)
    }

    fn clear_item(&mut self, id: &str) {
        if let Some(entry) = self.entries.get_mut(id) {
            entry.item = None;
        }
    }

    fn remove(&mut self, id: &str) {
        self.entries.remove(id);
    }

    fn ids_for_sender_path(&self, sender: &str, path: &str) -> Vec<String> {
        self.entries
            .iter()
            .filter(|(_, entry)| entry.owner == sender && entry.path == path)
            .map(|(id, _)| id.clone())
            .collect()
    }

    fn ids_for_owner_change(&self, name: &str, old_owner: &str) -> Vec<String> {
        self.entries
            .iter()
            .filter(|(_, entry)| {
                entry.bus_name == name
                    || entry.owner == name
                    || (!old_owner.is_empty() && entry.owner == old_owner)
            })
            .map(|(id, _)| id.clone())
            .collect()
    }

    fn snapshot(&self) -> Vec<TrayItem> {
        let mut items: Vec<_> = self
            .entries
            .values()
            .filter_map(|entry| entry.item.clone())
            .collect();
        items.sort_by(|a, b| (&a.app_id, &a.id).cmp(&(&b.app_id, &b.id)));
        items
    }
}

#[derive(Debug, Default, PartialEq, Eq)]
struct RefreshPlan {
    full_resync: bool,
    refresh_ids: bool,
    dirty_ids: BTreeSet<String>,
}

enum TraySignal<'a> {
    ItemPropertyChanged { sender: &'a str, path: &'a str },
    WatcherRegistered { service: Option<&'a str> },
    WatcherUnregistered,
    NameOwnerChanged { name: &'a str, old_owner: &'a str },
}

fn record_tray_signal(
    tracker: &ItemTracker,
    signal: TraySignal<'_>,
    plan: &mut RefreshPlan,
) -> bool {
    match signal {
        TraySignal::ItemPropertyChanged { sender, path } => {
            let matched = tracker.ids_for_sender_path(sender, path);
            if matched.is_empty() {
                return false;
            }
            plan.dirty_ids.extend(matched);
            true
        }
        TraySignal::WatcherRegistered { service } => {
            plan.refresh_ids = true;
            if let Some(service) = service {
                plan.dirty_ids.insert(normalize_id(service.to_owned()));
            }
            true
        }
        TraySignal::WatcherUnregistered => {
            plan.refresh_ids = true;
            true
        }
        TraySignal::NameOwnerChanged { name, old_owner } => {
            if name == WATCHER {
                plan.full_resync = true;
                return true;
            }
            let matched = tracker.ids_for_owner_change(name, old_owner);
            if matched.is_empty() {
                return false;
            }
            plan.refresh_ids = true;
            plan.dirty_ids.extend(matched);
            true
        }
    }
}

fn record_message(message: &zbus::Message, tracker: &ItemTracker, plan: &mut RefreshPlan) -> bool {
    let header = message.header();
    let interface = header.interface().map(|i| i.as_str());
    let member = header.member().map(|m| m.as_str());
    match (interface, member) {
        (Some(ITEM), Some(member)) if ITEM_SIGNALS.contains(&member) => {
            let Some(sender) = header.sender().map(|s| s.as_str()) else {
                return false;
            };
            let Some(path) = header.path().map(|p| p.as_str()) else {
                return false;
            };
            record_tray_signal(
                tracker,
                TraySignal::ItemPropertyChanged { sender, path },
                plan,
            )
        }
        (Some(WATCHER), Some("StatusNotifierItemRegistered")) => {
            let service = message.body().deserialize::<String>().ok();
            record_tray_signal(
                tracker,
                TraySignal::WatcherRegistered {
                    service: service.as_deref(),
                },
                plan,
            )
        }
        (Some(WATCHER), Some("StatusNotifierItemUnregistered")) => {
            record_tray_signal(tracker, TraySignal::WatcherUnregistered, plan)
        }
        (Some("org.freedesktop.DBus"), Some("NameOwnerChanged")) => {
            let Ok((name, old_owner, _new_owner)) =
                message.body().deserialize::<(String, String, String)>()
            else {
                return false;
            };
            record_tray_signal(
                tracker,
                TraySignal::NameOwnerChanged {
                    name: &name,
                    old_owner: &old_owner,
                },
                plan,
            )
        }
        _ => false,
    }
}

fn replace_changed(previous: &mut Option<Vec<TrayItem>>, next: Vec<TrayItem>) -> bool {
    if previous.as_ref() == Some(&next) {
        return false;
    }
    *previous = Some(next);
    true
}

async fn ensure_host(host: &Host, dbus: &zbus::fdo::DBusProxy<'_>) -> Result<(), String> {
    let watcher_name = zbus::names::BusName::try_from(WATCHER).unwrap();
    let owner = match dbus.get_name_owner(watcher_name.clone()).await {
        Ok(owner) => owner,
        Err(_) => {
            let _ = host.connection.request_name(WATCHER).await;
            dbus.get_name_owner(watcher_name)
                .await
                .map_err(|e| e.to_string())?
        }
    };
    let mut registered = host.registered_with.lock().await;
    if registered.as_deref() != Some(owner.as_str()) {
        let proxy = zbus::Proxy::new(&host.connection, owner.as_str(), WATCHER_PATH, WATCHER)
            .await
            .map_err(|e| e.to_string())?;
        proxy
            .call::<_, _, ()>(
                "RegisterStatusNotifierHost",
                &(host.connection.unique_name().unwrap().as_str(),),
            )
            .await
            .map_err(|e| e.to_string())?;
        *registered = Some(owner.to_string());
    }
    Ok(())
}

async fn read_tracked_item(
    connection: &zbus::Connection,
    dbus: &zbus::fdo::DBusProxy<'_>,
    id: String,
) -> Result<TrackedEntry, String> {
    let (name, path) = target(&id)?;
    let owner = if name.starts_with(':') {
        name.to_owned()
    } else {
        let bus_name = zbus::names::BusName::try_from(name).map_err(|e| e.to_string())?;
        dbus.get_name_owner(bus_name)
            .await
            .map_err(|e| e.to_string())?
            .to_string()
    };
    let values = properties_for_target(connection, &owner, path).await?;
    let status = string(&values, "Status");
    if status == "Passive" {
        return Ok(TrackedEntry {
            bus_name: name.to_owned(),
            owner,
            path: path.to_owned(),
            item: None,
        });
    }
    let attention = status == "NeedsAttention";
    let (mut width, mut height, mut argb) = pixmap(
        &values,
        if attention {
            "AttentionIconPixmap"
        } else {
            "IconPixmap"
        },
    );
    let mut icon_name = string(
        &values,
        if attention {
            "AttentionIconName"
        } else {
            "IconName"
        },
    );
    if attention && argb.is_empty() && icon_name.is_empty() {
        (width, height, argb) = pixmap(&values, "IconPixmap");
        icon_name = string(&values, "IconName");
    }
    let executable = match dbus
        .get_connection_unix_process_id(owner.as_str().try_into().unwrap())
        .await
    {
        Ok(pid) => std::fs::read_link(format!("/proc/{pid}/exe"))
            .ok()
            .and_then(|path| {
                path.file_name()?
                    .to_str()
                    .map(|name| name.trim_end_matches(" (deleted)").to_owned())
            }),
        Err(_) => None,
    };
    let item_id = string(&values, "Id");
    let title = string(&values, "Title");
    // Chromium-based applications can export the same item ID.
    let app_id = match (&executable, item_id.is_empty()) {
        (Some(executable), false) => format!("{executable}/{item_id}"),
        (Some(executable), true) => executable.clone(),
        (None, _) => item_id.clone(),
    };
    Ok(TrackedEntry {
        bus_name: name.to_owned(),
        owner,
        path: path.to_owned(),
        item: Some(TrayItem {
            id,
            title: if title.is_empty() {
                executable.unwrap_or(item_id)
            } else {
                title
            },
            app_id,
            icon_theme_path: string(&values, "IconThemePath"),
            icon_name,
            icon_argb: argb,
            icon_width: width,
            icon_height: height,
            item_is_menu: boolean(&values, "ItemIsMenu", false),
            has_menu: values
                .get("Menu")
                .and_then(|v| <&zbus::zvariant::ObjectPath>::try_from(v).ok())
                .is_some_and(|p| p.as_str() != "/" && p.as_str() != "/NO_DBUSMENU"),
            attention,
        }),
    })
}

enum ReadOutcome {
    Loaded(String, Box<TrackedEntry>),
    Removed(String),
    Failed(String),
}

async fn read_entries(
    host: &'static Host,
    dbus: &zbus::fdo::DBusProxy<'static>,
    ids: impl IntoIterator<Item = String>,
) -> Vec<ReadOutcome> {
    let mut tasks = tokio::task::JoinSet::new();
    for id in ids {
        let Ok((name, _)) = target(&id) else {
            continue;
        };
        let name = zbus::names::BusName::try_from(name).unwrap().to_owned();
        let dbus = dbus.clone();
        tasks.spawn(async move {
            match tokio::time::timeout(
                Duration::from_millis(350),
                read_tracked_item(&host.connection, &dbus, id.clone()),
            )
            .await
            {
                Ok(Ok(entry)) => ReadOutcome::Loaded(id, Box::new(entry)),
                _ => {
                    if dbus.name_has_owner(name).await == Ok(false) {
                        if host.watcher.items.lock().await.remove(&id)
                            && let Ok(emitter) = zbus::object_server::SignalEmitter::new(
                                &host.connection,
                                WATCHER_PATH,
                            )
                        {
                            let _ = Watcher::status_notifier_item_unregistered(&emitter, &id).await;
                        }
                        ReadOutcome::Removed(id)
                    } else {
                        ReadOutcome::Failed(id)
                    }
                }
            }
        });
    }
    let mut outcomes = vec![];
    while let Some(outcome) = tasks.join_next().await {
        if let Ok(outcome) = outcome {
            outcomes.push(outcome);
        }
    }
    outcomes
}

async fn bounded_registered_ids(host: &Host) -> Result<BTreeSet<String>, String> {
    Ok(registered_ids(host)
        .await?
        .into_iter()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .take(128)
        .collect())
}

pub(crate) async fn items() -> Result<Vec<TrayItem>, String> {
    tokio::time::timeout(Duration::from_secs(3), async {
        let host = host().await?;
        let dbus = zbus::fdo::DBusProxy::new(&host.connection)
            .await
            .map_err(|e| e.to_string())?;
        ensure_host(host, &dbus).await?;
        let ids = bounded_registered_ids(host).await?;
        let mut tracker = ItemTracker::default();
        for outcome in read_entries(host, &dbus, ids).await {
            if let ReadOutcome::Loaded(id, entry) = outcome {
                tracker.upsert(id, *entry);
            }
        }
        Ok(tracker.snapshot())
    })
    .await
    .map_err(|_| "Tray query timed out".to_string())?
}

async fn apply_refresh_plan(
    host: &'static Host,
    tracker: &mut ItemTracker,
    plan: RefreshPlan,
) -> Result<(), String> {
    tokio::time::timeout(Duration::from_secs(3), async {
        let dbus = zbus::fdo::DBusProxy::new(&host.connection)
            .await
            .map_err(|e| e.to_string())?;
        let target_ids: BTreeSet<String> = if plan.full_resync {
            ensure_host(host, &dbus).await?;
            let ids = bounded_registered_ids(host).await?;
            tracker.retain_ids(&ids);
            ids
        } else if plan.refresh_ids {
            ensure_host(host, &dbus).await?;
            let ids = bounded_registered_ids(host).await?;
            tracker.retain_ids(&ids);
            let mut to_read = plan.dirty_ids;
            to_read.retain(|id| ids.contains(id));
            for id in &ids {
                if !tracker.contains(id) {
                    to_read.insert(id.clone());
                }
            }
            to_read
        } else {
            plan.dirty_ids
                .into_iter()
                .filter(|id| tracker.contains(id))
                .collect()
        };

        for outcome in read_entries(host, &dbus, target_ids).await {
            match outcome {
                ReadOutcome::Loaded(id, entry) => tracker.upsert(id, *entry),
                ReadOutcome::Removed(id) => tracker.remove(&id),
                ReadOutcome::Failed(id) => tracker.clear_item(&id),
            }
        }
        Ok::<(), String>(())
    })
    .await
    .map_err(|_| "Tray query timed out".to_string())?
}

pub(crate) async fn subscribe(sink: StreamSink<Vec<TrayItem>>) {
    let mut backoff = 1;
    loop {
        match watch_tray(&sink, &mut backoff).await {
            Ok(()) => return,
            Err(error) => {
                if sink.add_error(error).is_err() {
                    return;
                }
                tokio::time::sleep(Duration::from_secs(backoff)).await;
                backoff = (backoff * 2).min(5);
            }
        }
    }
}

async fn watch_tray(sink: &StreamSink<Vec<TrayItem>>, backoff: &mut u64) -> Result<(), String> {
    let host = tokio::time::timeout(Duration::from_secs(2), host())
        .await
        .map_err(|_| "Tray connection timed out".to_string())??;
    watch_connection(sink, host, backoff).await
}

async fn watch_connection(
    sink: &StreamSink<Vec<TrayItem>>,
    host: &'static Host,
    backoff: &mut u64,
) -> Result<(), String> {
    let mut rules = Vec::with_capacity(ITEM_SIGNALS.len() + 3);
    for member in ITEM_SIGNALS {
        rules.push(
            zbus::MatchRule::builder()
                .msg_type(zbus::message::Type::Signal)
                .interface(ITEM)
                .unwrap()
                .member(*member)
                .unwrap()
                .build(),
        );
    }
    for member in [
        "StatusNotifierItemRegistered",
        "StatusNotifierItemUnregistered",
    ] {
        rules.push(
            zbus::MatchRule::builder()
                .msg_type(zbus::message::Type::Signal)
                .interface(WATCHER)
                .unwrap()
                .member(member)
                .unwrap()
                .build(),
        );
    }
    rules.push(
        zbus::MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .sender("org.freedesktop.DBus")
            .unwrap()
            .interface("org.freedesktop.DBus")
            .unwrap()
            .member("NameOwnerChanged")
            .unwrap()
            .build(),
    );
    let mut streams = Vec::with_capacity(rules.len());
    for rule in rules {
        let messages = tokio::time::timeout(
            Duration::from_secs(2),
            zbus::MessageStream::for_match_rule(rule, &host.connection, Some(64)),
        )
        .await
        .map_err(|_| "Tray subscription timed out".to_string())?
        .map_err(|error| error.to_string())?;
        streams.push(messages);
    }
    let mut signals = stream::select_all(streams);
    let mut tracker = ItemTracker::default();
    let mut previous = None;
    let mut plan = RefreshPlan {
        full_resync: true,
        ..Default::default()
    };

    loop {
        apply_refresh_plan(host, &mut tracker, plan).await?;
        *backoff = 1;
        if replace_changed(&mut previous, tracker.snapshot())
            && sink.add(previous.as_ref().unwrap().clone()).is_err()
        {
            return Ok(());
        }

        let mut next_plan = RefreshPlan::default();
        let deadline = tokio::time::Instant::now() + Duration::from_secs(60);
        loop {
            match tokio::time::timeout_at(deadline, signals.next()).await {
                Ok(Some(Ok(message))) => {
                    if record_message(&message, &tracker, &mut next_plan) {
                        break;
                    }
                }
                Ok(Some(Err(error))) => return Err(error.to_string()),
                Ok(None) => return Err("Tray signal stream closed".into()),
                Err(_) => {
                    next_plan.full_resync = true;
                    break;
                }
            }
        }
        if !next_plan.full_resync {
            tokio::time::sleep(Duration::from_millis(50)).await;
            loop {
                match signals.next().now_or_never() {
                    Some(Some(Ok(message))) => {
                        let _ = record_message(&message, &tracker, &mut next_plan);
                    }
                    Some(Some(Err(error))) => return Err(error.to_string()),
                    Some(None) => return Err("Tray signal stream closed".into()),
                    None => break,
                }
            }
        }
        plan = next_plan;
    }
}

async fn registered(
    id: &str,
) -> Result<(&'static zbus::Connection, zbus::names::OwnedUniqueName), String> {
    let (name, _) = target(id)?;
    let host = host().await?;
    if !registered_ids(host).await?.iter().any(|v| v == id) {
        return Err("Tray item is no longer registered".into());
    }
    let dbus = zbus::fdo::DBusProxy::new(&host.connection)
        .await
        .map_err(|e| e.to_string())?;
    let owner = dbus
        .get_name_owner(
            name.try_into()
                .map_err(|e: zbus::names::Error| e.to_string())?,
        )
        .await
        .map_err(|e| e.to_string())?;
    Ok((&host.connection, owner))
}

pub(crate) async fn action(id: &str, action: &str, delta: i32) -> Result<(), String> {
    if ![
        "activate",
        "secondary",
        "context",
        "scroll",
        "scrollHorizontal",
    ]
    .contains(&action)
    {
        return Err("Unknown tray action".into());
    }
    tokio::time::timeout(Duration::from_secs(2), async {
        let (connection, owner) = registered(id).await?;
        let (_, path) = target(id)?;
        let proxy = zbus::Proxy::new(connection, owner.as_str(), path, ITEM)
            .await
            .map_err(|e| e.to_string())?;
        let result = if action.starts_with("scroll") {
            proxy
                .call::<_, _, ()>(
                    "Scroll",
                    &(
                        delta.clamp(-120, 120),
                        if action == "scroll" {
                            "vertical"
                        } else {
                            "horizontal"
                        },
                    ),
                )
                .await
        } else {
            proxy
                .call::<_, _, ()>(
                    match action {
                        "activate" => "Activate",
                        "secondary" => "SecondaryActivate",
                        _ => "ContextMenu",
                    },
                    &(0_i32, 0_i32),
                )
                .await
        };
        result.map_err(|e| e.to_string())
    })
    .await
    .map_err(|_| "Tray action timed out".to_string())?
}
