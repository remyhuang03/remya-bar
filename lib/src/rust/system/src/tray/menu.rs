use crate::api::TrayMenuEntry;
use std::time::Duration;
use zbus::zvariant::{OwnedValue, Value};

use super::{Properties, boolean, properties, registered, string, target};

pub(super) type Layout = (i32, Properties, Vec<OwnedValue>);

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

pub(super) fn menu_label(label: &str) -> String {
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

pub(super) fn menu_entries(layout: Layout) -> Vec<TrayMenuEntry> {
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
