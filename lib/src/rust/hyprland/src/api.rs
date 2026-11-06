use crate::frb_generated::StreamSink;
use std::sync::OnceLock;
use std::time::Duration;
use tokio::sync::{broadcast, watch};

struct Hub {
    events: broadcast::Sender<HyprlandUpdate>,
    status: watch::Sender<Option<HyprlandUpdate>>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HyprlandUpdate {
    /// connected, disconnected, event, resync, or heartbeat.
    pub kind: String,
    pub name: String,
    /// Raw payload: commas and future event names are preserved.
    pub data: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HyprlandWindow {
    pub address: String,
    pub title: String,
    pub app_id: String,
    pub workspace_id: i32,
    pub monitor_name: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HyprlandWorkspace {
    pub id: i32,
    pub name: String,
    pub monitor_name: String,
    pub window_count: u32,
    pub windows: Vec<HyprlandWindow>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HyprlandWorkspaceSlot {
    pub id: i32,
    pub name: String,
    pub active: bool,
    pub occupied: bool,
    pub window_count: u32,
    pub app_id: Option<String>,
    pub title: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HyprlandMonitor {
    pub name: String,
    pub x: i32,
    pub y: i32,
    pub active_workspace_id: i32,
    pub special_workspace_id: Option<i32>,
    pub special_workspace_name: Option<String>,
    pub current_window: Option<HyprlandWindow>,
    pub workspace_slots: Vec<HyprlandWorkspaceSlot>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HyprlandSnapshot {
    pub monitors: Vec<HyprlandMonitor>,
    pub workspaces: Vec<HyprlandWorkspace>,
}

pub async fn hyprland_snapshot() -> Result<HyprlandSnapshot, String> {
    let monitors = hyprland_request("j/monitors".into()).await?;
    let workspaces = hyprland_request("j/workspaces".into()).await?;
    let clients = hyprland_request("j/clients".into()).await?;
    let active_window = hyprland_request("j/activewindow".into()).await?;
    crate::workspace_state::parse(&monitors, &workspaces, &clients, &active_window)
}

pub async fn hyprland_switch_workspace(
    output_name: String,
    workspace_id: i32,
) -> Result<(), String> {
    let snapshot = hyprland_snapshot().await?;
    let command = crate::workspace_state::switch_command(&snapshot, &output_name, workspace_id)?;
    dispatch_workspace_command(command).await
}

pub async fn hyprland_scroll_workspace(output_name: String, direction: i32) -> Result<(), String> {
    let snapshot = hyprland_snapshot().await?;
    let command = crate::workspace_state::scroll_command(&snapshot, &output_name, direction)?;
    dispatch_workspace_command(command).await
}

pub async fn hyprland_toggle_special(output_name: String) -> Result<(), String> {
    let snapshot = hyprland_snapshot().await?;
    let command = crate::workspace_state::special_command(&snapshot, &output_name)?;
    dispatch_workspace_command(command).await
}

async fn dispatch_workspace_command(command: String) -> Result<(), String> {
    let reply = hyprland_request(command).await?;
    if reply.trim() != "ok" {
        return Err(format!("Workspace switch failed: {reply}"));
    }
    Ok(())
}

pub async fn hyprland_request(command: String) -> Result<String, String> {
    let directory = crate::ipc::socket_directory().map_err(|error| error.to_string())?;
    crate::ipc::request(&directory, &command)
        .await
        .map_err(|error| error.to_string())
}

pub async fn subscribe_hyprland(sink: StreamSink<HyprlandUpdate>) {
    static EVENTS: OnceLock<Hub> = OnceLock::new();
    let hub = EVENTS.get_or_init(|| {
        let (events, _) = broadcast::channel(256);
        let (status, _) = watch::channel(None);
        tokio::spawn(crate::ipc::listen(events.clone(), status.clone()));
        Hub { events, status }
    });
    let mut receiver = hub.events.subscribe();
    let initial = hub.status.borrow().clone();
    if let Some(update) = initial
        && sink.add(update).is_err()
    {
        return;
    }
    loop {
        let update = match tokio::time::timeout(Duration::from_secs(1), receiver.recv()).await {
            Ok(Ok(update)) => update,
            Ok(Err(broadcast::error::RecvError::Lagged(_))) => HyprlandUpdate {
                kind: "resync".into(),
                name: String::new(),
                data: "Event consumer fell behind; refresh component state".into(),
            },
            Ok(Err(broadcast::error::RecvError::Closed)) => break,
            Err(_) => HyprlandUpdate {
                kind: "heartbeat".into(),
                name: String::new(),
                data: String::new(),
            },
        };
        // A heartbeat also releases subscriptions belonging to destroyed engines.
        if sink.add(update).is_err() {
            break;
        }
    }
}

pub async fn hyprland_output_fullscreen(x: i32, y: i32) -> Result<bool, String> {
    let monitors = hyprland_request("j/monitors".into()).await?;
    let clients = hyprland_request("j/clients".into()).await?;
    let parse = |input: &str| {
        serde_json::from_str::<Vec<serde_json::Value>>(input).map_err(|error| error.to_string())
    };
    Ok(output_fullscreen(
        &parse(&monitors)?,
        &parse(&clients)?,
        x,
        y,
    ))
}

fn output_fullscreen(
    monitors: &[serde_json::Value],
    clients: &[serde_json::Value],
    x: i32,
    y: i32,
) -> bool {
    let mut matches = monitors.iter().filter(|m| m["x"] == x && m["y"] == y);
    let Some(monitor) = matches.next() else {
        return false;
    };
    let Some(id) = monitor["id"].as_i64() else {
        return false;
    };
    if matches.next().is_some() {
        return false;
    }
    let active = monitor["activeWorkspace"]["id"].as_i64();
    let special = monitor["specialWorkspace"]["id"]
        .as_i64()
        .filter(|&id| id != 0);
    clients.iter().any(|client| {
        let workspace = client["workspace"]["id"].as_i64();
        client["monitor"] == id
            && client["mapped"] == true
            && client["hidden"] == false
            && client["fullscreen"]
                .as_u64()
                .is_some_and(|mode| mode & 2 != 0)
            && workspace.is_some()
            && (workspace == active || workspace == special)
    })
}

#[cfg(test)]
mod fullscreen_tests {
    use super::output_fullscreen;
    use serde_json::json;

    #[test]
    fn only_visible_fullscreen_clients_hide_their_output_bar() {
        let monitors = [
            json!({"id": 1, "x": 0, "y": 0, "activeWorkspace": {"id": 2}, "specialWorkspace": {"id": -99}}),
        ];
        let mut client = json!({"monitor": 1, "mapped": true, "hidden": false, "fullscreen": 2, "workspace": {"id": -99}});
        assert!(output_fullscreen(&monitors, &[client.clone()], 0, 0));
        assert!(!output_fullscreen(&monitors, &[client.clone()], 1, 0));
        client["workspace"]["id"] = json!(3);
        assert!(!output_fullscreen(&monitors, &[client.clone()], 0, 0));
        client["workspace"]["id"] = json!(2);
        client["fullscreen"] = json!(1);
        assert!(!output_fullscreen(&monitors, &[client], 0, 0));
    }
}
