use crate::frb_generated::StreamSink;
use std::collections::HashSet;
use std::sync::{
    Arc, OnceLock,
    atomic::{AtomicBool, Ordering},
};
use std::time::Duration;
use tokio::sync::{Notify, broadcast, watch};

struct Hub {
    events: broadcast::Sender<HyprlandUpdate>,
    status: watch::Sender<Option<HyprlandUpdate>>,
    super_held: AtomicBool,
    subscriber_added: Notify,
}

impl Hub {
    fn new() -> Self {
        let (events, _) = broadcast::channel(256);
        let (status, _) = watch::channel(None);
        Self {
            events,
            status,
            super_held: AtomicBool::new(false),
            subscriber_added: Notify::new(),
        }
    }

    fn subscribe(&self) -> broadcast::Receiver<HyprlandUpdate> {
        let receiver = self.events.subscribe();
        self.subscriber_added.notify_one();
        receiver
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HyprlandUpdate {
    /// connected, disconnected, event, modifier, resync, or heartbeat.
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
    pub workspace_address: Option<String>,
    pub monitor_name: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HyprlandWorkspace {
    pub address: String,
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
    pub owner: Option<String>,
    pub apps: Vec<String>,
    pub urgent: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HyprlandMonitor {
    pub name: String,
    pub output_number: u32,
    pub x: i32,
    pub y: i32,
    pub active_workspace_address: String,
    pub special_workspace_address: Option<String>,
    pub special_workspace_name: Option<String>,
    pub fullscreen: bool,
    pub current_window: Option<HyprlandWindow>,
    pub workspace_slots: Vec<HyprlandWorkspaceSlot>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HyprlandSnapshot {
    pub monitors: Vec<HyprlandMonitor>,
    pub workspaces: Vec<HyprlandWorkspace>,
    pub focused_output: Option<String>,
}

/// Captures a snapshot with the caller's workspace slots per numbered group.
pub async fn hyprland_snapshot(slot_count: u8) -> Result<HyprlandSnapshot, String> {
    if !(1..=10).contains(&slot_count) {
        return Err("Workspace count must be between 1 and 10".into());
    }
    let monitors = hyprland_request("j/monitors".into()).await?;
    let workspaces = hyprland_request("j/workspaces".into()).await?;
    let clients = hyprland_request("j/clients".into()).await?;
    let active_window = hyprland_request("j/activewindow".into()).await?;
    let urgent = hyprland_request(
        "repl local ids = {}; for _, ws in ipairs(hl.get_workspaces()) do if ws.has_urgent and ws.id then table.insert(ids, ws.id) end end; return 'urgent:' .. table.concat(ids, ',')".into(),
    ).await?;
    let urgent = urgent
        .trim()
        .strip_prefix("urgent:")
        .ok_or("Invalid urgent workspace reply")?;
    let urgent = urgent
        .split(',')
        .filter(|id| !id.is_empty())
        .map(str::parse)
        .collect::<Result<HashSet<i32>, _>>()
        .map_err(|e| e.to_string())?;
    crate::workspace_state::parse(
        &monitors,
        &workspaces,
        &clients,
        &active_window,
        &urgent,
        slot_count,
    )
}

pub async fn hyprland_switch_workspace(
    output_name: String,
    workspace_address: String,
    slot_count: u8,
) -> Result<(), String> {
    let snapshot = hyprland_snapshot(slot_count).await?;
    let command =
        crate::workspace_state::switch_command(&snapshot, &output_name, &workspace_address)?;
    dispatch_workspace_command(command).await
}

pub async fn hyprland_scroll_workspace(
    output_name: String,
    direction: i32,
    slot_count: u8,
) -> Result<(), String> {
    let snapshot = hyprland_snapshot(slot_count).await?;
    let command = crate::workspace_state::scroll_command(&snapshot, &output_name, direction)?;
    dispatch_workspace_command(command).await
}

pub async fn hyprland_toggle_special(output_name: String, slot_count: u8) -> Result<(), String> {
    let snapshot = hyprland_snapshot(slot_count).await?;
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
    static EVENTS: OnceLock<Arc<Hub>> = OnceLock::new();
    let hub = EVENTS.get_or_init(|| {
        let hub = Arc::new(Hub::new());
        tokio::spawn(crate::ipc::listen(hub.events.clone(), hub.status.clone()));
        tokio::spawn(watch_super(hub.clone(), read_super));
        hub
    });
    let mut receiver = hub.subscribe();
    let initial = hub.status.borrow().clone();
    if let Some(update) = initial
        && sink.add(update).is_err()
    {
        return;
    }
    if sink
        .add(super_update(hub.super_held.load(Ordering::Relaxed)))
        .is_err()
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
        let resync = update.kind == "resync";
        // A heartbeat also releases subscriptions belonging to destroyed engines.
        if sink.add(update).is_err()
            || resync
                && sink
                    .add(super_update(hub.super_held.load(Ordering::Relaxed)))
                    .is_err()
        {
            break;
        }
    }
}

fn super_update(held: bool) -> HyprlandUpdate {
    HyprlandUpdate {
        kind: "modifier".into(),
        name: "super".into(),
        data: held.to_string(),
    }
}

async fn watch_super<F: Future<Output = bool>>(hub: Arc<Hub>, read: impl Fn() -> F) {
    // One compositor read serves all bar views without taking keyboard focus.
    let mut status = hub.status.subscribe();
    loop {
        if hub.events.receiver_count() == 0 {
            hub.super_held.store(false, Ordering::Relaxed);
            hub.subscriber_added.notified().await;
            continue;
        }
        if !status
            .borrow()
            .as_ref()
            .is_some_and(|update| update.kind == "connected")
        {
            publish_super(&hub, false);
            if status
                .wait_for(|update| {
                    update
                        .as_ref()
                        .is_some_and(|update| update.kind == "connected")
                })
                .await
                .is_err()
            {
                return;
            }
            continue;
        }
        publish_super(&hub, read().await);
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

async fn read_super() -> bool {
    hyprland_request(
        "repl return tostring(hl.is_key_down('Super_L') or hl.is_key_down('Super_R'))".into(),
    )
    .await
    .is_ok_and(|reply| reply.trim() == "true")
}

fn publish_super(hub: &Hub, held: bool) {
    if hub.super_held.swap(held, Ordering::Relaxed) != held {
        let _ = hub.events.send(super_update(held));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn super_polls_only_with_a_connection_and_subscriber() {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(async {
                let hub = Arc::new(Hub::new());
                let (samples, mut reads) = tokio::sync::mpsc::unbounded_channel();
                let worker = tokio::spawn(watch_super(hub.clone(), move || {
                    samples.send(()).unwrap();
                    std::future::ready(true)
                }));
                let initial = hub.subscribe();
                let interval = Duration::from_millis(150);
                assert!(tokio::time::timeout(interval, reads.recv()).await.is_err());
                drop(initial);
                hub.status.send_replace(Some(HyprlandUpdate {
                    kind: "connected".into(),
                    name: String::new(),
                    data: String::new(),
                }));
                assert!(tokio::time::timeout(interval, reads.recv()).await.is_err());
                let mut subscribed = hub.subscribe();
                assert_eq!(
                    tokio::time::timeout(Duration::from_secs(1), subscribed.recv())
                        .await
                        .unwrap()
                        .unwrap(),
                    super_update(true)
                );
                assert_eq!(reads.try_recv(), Ok(()));
                drop(subscribed);
                assert!(tokio::time::timeout(interval, reads.recv()).await.is_err());
                worker.abort();
            });
    }
}
