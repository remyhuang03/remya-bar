use crate::api::{TrayItem, TrayMenuEntry};
use std::collections::{BTreeSet, HashMap};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};
use zbus::zvariant::{OwnedValue, Value};

const WATCHER: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";
const ITEM: &str = "org.kde.StatusNotifierItem";
type Properties = HashMap<String, OwnedValue>;
type Layout = (i32, Properties, Vec<OwnedValue>);

#[derive(Clone, Default)]
struct Watcher {
    items: Arc<tokio::sync::Mutex<BTreeSet<String>>>,
}

#[zbus::interface(name = "org.kde.StatusNotifierWatcher")]
impl Watcher {
    async fn register_status_notifier_item(
        &self,
        service: String,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        let sender = header
            .sender()
            .ok_or_else(|| zbus::fdo::Error::InvalidArgs("Missing sender".into()))?;
        let id = if service.starts_with('/') {
            format!("{sender}{service}")
        } else {
            let connection = emitter.connection();
            let dbus = zbus::fdo::DBusProxy::new(connection).await?;
            let name = zbus::names::BusName::try_from(service)
                .map_err(|error| zbus::fdo::Error::InvalidArgs(error.to_string()))?;
            if dbus.get_name_owner(name).await?.as_str() != sender.as_str() {
                return Err(zbus::fdo::Error::AccessDenied(
                    "Tray service belongs to another client".into(),
                ));
            }
            format!("{sender}/StatusNotifierItem")
        };
        target(&id).map_err(zbus::fdo::Error::InvalidArgs)?;
        if self.items.lock().await.insert(id.clone()) {
            Self::status_notifier_item_registered(&emitter, &id).await?;
        }
        Ok(())
    }

    async fn register_status_notifier_host(&self, _service: String) {}

    #[zbus(property)]
    async fn registered_status_notifier_items(&self) -> Vec<String> {
        self.items.lock().await.iter().cloned().collect()
    }
    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn protocol_version(&self) -> i32 {
        0
    }
    #[zbus(signal)]
    async fn status_notifier_item_registered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn status_notifier_item_unregistered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn status_notifier_host_registered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::Result<()>;
}

struct Host {
    connection: zbus::Connection,
    watcher: Watcher,
    registered_with: tokio::sync::Mutex<Option<String>>,
    snapshot: tokio::sync::Mutex<Option<(Instant, Vec<TrayItem>)>>,
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
                snapshot: Default::default(),
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
async fn properties(connection: &zbus::Connection, id: &str) -> Result<Properties, String> {
    let (name, path) = target(id)?;
    let proxy = zbus::Proxy::new(connection, name, path, "org.freedesktop.DBus.Properties")
        .await
        .map_err(|e| e.to_string())?;
    proxy
        .call("GetAll", &(ITEM,))
        .await
        .map_err(|e| e.to_string())
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

async fn read_item(
    connection: &zbus::Connection,
    dbus: &zbus::fdo::DBusProxy<'_>,
    id: String,
) -> Result<Option<TrayItem>, String> {
    let values = properties(connection, &id).await?;
    let status = string(&values, "Status");
    if status == "Passive" {
        return Ok(None);
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
    let (name, _) = target(&id)?;
    let executable = match dbus
        .get_connection_unix_process_id(name.try_into().unwrap())
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
    Ok(Some(TrayItem {
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
    }))
}

pub(crate) async fn items() -> Result<Vec<TrayItem>, String> {
    tokio::time::timeout(Duration::from_secs(3), async {
        let host = host().await?;
        let mut snapshot = host.snapshot.lock().await;
        if let Some((sampled, items)) = snapshot.as_ref()
            && sampled.elapsed() < Duration::from_millis(750)
        {
            return Ok(items.clone());
        }
        let dbus = zbus::fdo::DBusProxy::new(&host.connection)
            .await
            .map_err(|e| e.to_string())?;
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
        drop(registered);

        let mut result = vec![];
        let mut tasks = tokio::task::JoinSet::new();
        for id in registered_ids(host)
            .await?
            .into_iter()
            .collect::<BTreeSet<_>>()
            .into_iter()
            .take(128)
        {
            let Ok((name, _)) = target(&id) else { continue };
            let name = zbus::names::BusName::try_from(name).unwrap().to_owned();
            let dbus = dbus.clone();
            tasks.spawn(async move {
                match tokio::time::timeout(
                    Duration::from_millis(350),
                    read_item(&host.connection, &dbus, id.clone()),
                )
                .await
                {
                    Ok(Ok(item)) => item,
                    _ => {
                        if dbus.name_has_owner(name).await == Ok(false)
                            && host.watcher.items.lock().await.remove(&id)
                            && let Ok(emitter) = zbus::object_server::SignalEmitter::new(
                                &host.connection,
                                WATCHER_PATH,
                            )
                        {
                            let _ = Watcher::status_notifier_item_unregistered(&emitter, &id).await;
                        }
                        None
                    }
                }
            });
        }
        while let Some(item) = tasks.join_next().await {
            if let Ok(Some(item)) = item {
                result.push(item);
            }
        }
        result.sort_by(|a, b| (&a.app_id, &a.id).cmp(&(&b.app_id, &b.id)));
        *snapshot = Some((Instant::now(), result.clone()));
        Ok(result)
    })
    .await
    .map_err(|_| "Tray query timed out".to_string())?
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
async fn menu_proxy(id: &str) -> Result<zbus::Proxy<'static>, String> {
    let (connection, owner) = registered(id).await?;
    let (_, path) = target(id)?;
    let values = properties(connection, &format!("{owner}{path}")).await?;
    let path = values
        .get("Menu")
        .and_then(|v| <&zbus::zvariant::ObjectPath>::try_from(v).ok())
        .ok_or("Tray menu unavailable")?;
    zbus::Proxy::new_owned(
        connection.clone(),
        owner,
        path.to_owned(),
        "com.canonical.dbusmenu",
    )
    .await
    .map_err(|e| e.to_string())
}
fn menu_label(label: &str) -> String {
    let mut chars = label.chars().peekable();
    let mut result = String::new();
    while let Some(ch) = chars.next() {
        if ch == '_' && chars.peek().is_some() {
            if chars.peek() == Some(&'_') {
                result.push(chars.next().unwrap());
            }
        } else {
            result.push(ch);
        }
    }
    result
}

fn menu_entries(layout: Layout) -> Vec<TrayMenuEntry> {
    layout
        .2
        .into_iter()
        .take(256)
        .filter_map(|value| {
            let (id, props, children) = Layout::try_from(value).ok()?;
            if !boolean(&props, "visible", true) {
                return None;
            }
            let icon_data = props
                .get("icon-data")
                .and_then(|v| v.try_clone().ok())
                .and_then(|v| Vec::<u8>::try_from(v).ok())
                .filter(|bytes| bytes.len() <= 262_144 && bytes.starts_with(b"\x89PNG\r\n\x1a\n"))
                .unwrap_or_default();
            Some(TrayMenuEntry {
                id,
                label: menu_label(&string(&props, "label")),
                enabled: boolean(&props, "enabled", true),
                separator: string(&props, "type") == "separator",
                submenu: !children.is_empty() || string(&props, "children-display") == "submenu",
                icon_name: string(&props, "icon-name"),
                icon_data,
                toggle_type: string(&props, "toggle-type"),
                toggle_state: props
                    .get("toggle-state")
                    .and_then(|v| i32::try_from(v).ok())
                    .unwrap_or(-1),
            })
        })
        .collect()
}

async fn menu_layout(proxy: &zbus::Proxy<'_>, parent: i32) -> Result<Vec<TrayMenuEntry>, String> {
    let (_, layout): (u32, Layout) = proxy
        .call("GetLayout", &(parent, 1_i32, Vec::<String>::new()))
        .await
        .map_err(|e| e.to_string())?;
    if layout.0 != parent {
        return Err("Tray menu section unavailable".into());
    }
    Ok(menu_entries(layout))
}

pub(crate) async fn menu(id: &str, parent: i32) -> Result<Vec<TrayMenuEntry>, String> {
    tokio::time::timeout(Duration::from_secs(2), async {
        let proxy = menu_proxy(id).await?;
        let _ = tokio::time::timeout(
            Duration::from_millis(750),
            proxy.call::<_, _, bool>("AboutToShow", &(parent,)),
        )
        .await;
        menu_layout(&proxy, parent).await
    })
    .await
    .map_err(|_| "Tray menu timed out".to_string())?
}

pub(crate) async fn menu_action(id: &str, parent: i32, entry: i32) -> Result<(), String> {
    tokio::time::timeout(Duration::from_secs(2), async {
        let proxy = menu_proxy(id).await?;
        if !menu_layout(&proxy, parent)
            .await?
            .iter()
            .any(|v| v.id == entry && v.enabled && !v.separator && !v.submenu)
        {
            return Err("Tray menu item unavailable".into());
        }
        proxy
            .call::<_, _, ()>("Event", &(entry, "clicked", Value::I32(0), 0_u32))
            .await
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|_| "Tray menu action timed out".to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_targets_and_pixmap_bounds() {
        assert!(target(":1.42/StatusNotifierItem").is_ok());
        assert!(target("not a bus/Item").is_err());
        assert!(target("org.example.App").is_err());
        let mut values = Properties::new();
        values.insert(
            "IconPixmap".into(),
            OwnedValue::try_from(Value::from(vec![(1_i32, 1_i32, vec![255_u8, 10, 20, 30])]))
                .unwrap(),
        );
        assert_eq!(pixmap(&values, "IconPixmap"), (1, 1, vec![255, 10, 20, 30]));
    }
    #[test]
    fn pixmap_prefers_a_source_large_enough_for_scaled_outputs() {
        let mut values = Properties::new();
        let candidates = [16_i32, 32, 64, 128]
            .into_iter()
            .map(|size| (size, size, vec![255_u8; (size * size * 4) as usize]))
            .collect::<Vec<_>>();
        values.insert(
            "IconPixmap".into(),
            OwnedValue::try_from(Value::from(candidates)).unwrap(),
        );
        assert_eq!(pixmap(&values, "IconPixmap").0, 64);
    }

    #[test]
    fn menus_preserve_enabled_and_toggle_state() {
        let mut properties = Properties::new();
        properties.insert("label".into(), zbus::zvariant::Str::from("_Open").into());
        properties.insert("enabled".into(), false.into());
        properties.insert("toggle-state".into(), 1_i32.into());
        let child = Value::from((7_i32, properties, Vec::<OwnedValue>::new()));
        assert_eq!(menu_label("_Open __ File"), "Open _ File");
        let entries = menu_entries((
            0,
            Properties::new(),
            vec![OwnedValue::try_from(child).unwrap()],
        ));
        assert_eq!(entries[0].label, "Open");
        assert!(!entries[0].enabled);
        assert_eq!(entries[0].toggle_state, 1);
    }
}
