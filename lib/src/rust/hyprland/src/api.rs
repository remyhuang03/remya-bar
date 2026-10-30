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
