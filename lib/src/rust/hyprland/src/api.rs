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
