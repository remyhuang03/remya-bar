use crate::api::MediaPlayerSnapshot;
use std::collections::HashMap;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use zbus::names::BusName;
use zbus::zvariant::ObjectPath;
use zbus::zvariant::OwnedValue;

const PATH: &str = "/org/mpris/MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";

type Properties = HashMap<String, OwnedValue>;

#[derive(Default)]
struct MediaState {
    selected: Option<String>,
    updated: Option<Instant>,
    players: Vec<MediaPlayerSnapshot>,
}

fn state() -> &'static Mutex<MediaState> {
    static STATE: OnceLock<Mutex<MediaState>> = OnceLock::new();
    STATE.get_or_init(Default::default)
}

fn is_player(name: &str) -> bool {
    name.starts_with("org.mpris.MediaPlayer2.") && name != "org.mpris.MediaPlayer2.playerctld"
}

pub(crate) async fn players() -> Result<Vec<MediaPlayerSnapshot>, String> {
    let mut state = state().lock().await;
    if state
        .updated
        .is_some_and(|time| time.elapsed() < Duration::from_millis(900))
    {
        return Ok(state.players.clone());
    }
    let (mut players, names) = tokio::time::timeout(Duration::from_secs(2), discover())
        .await
        .map_err(|_| "MPRIS query timed out".to_string())??;
    if state
        .selected
        .as_ref()
        .is_some_and(|selected| !names.contains(selected))
    {
        state.selected = None;
    }
    players.sort_by(|a, b| {
        let priority = |p: &MediaPlayerSnapshot| {
            (
                state.selected.as_ref() != Some(&p.bus_name),
                match p.playback_status.as_str() {
                    "Playing" => 0,
                    "Paused" => 1,
                    _ => 2,
                },
            )
        };
        priority(a)
            .cmp(&priority(b))
            .then_with(|| a.bus_name.cmp(&b.bus_name))
    });
    state.updated = Some(Instant::now());
    state.players = players.clone();
    Ok(players)
}

async fn discover() -> Result<(Vec<MediaPlayerSnapshot>, Vec<String>), String> {
    let connection = zbus::Connection::session()
        .await
        .map_err(|e| e.to_string())?;
    let dbus = zbus::fdo::DBusProxy::new(&connection)
        .await
        .map_err(|e| e.to_string())?;
    let names: Vec<_> = dbus
        .list_names()
        .await
        .map_err(|e| e.to_string())?
        .into_iter()
        .filter(|name| is_player(name.as_str()))
        .map(|name| name.to_string())
        .collect();
    let mut reads = tokio::task::JoinSet::new();
    for name in &names {
        let connection = connection.clone();
        let name = name.clone();
        reads.spawn(async move {
            tokio::time::timeout(Duration::from_millis(350), async {
                let owner = owner(&connection, &name).await?;
                read_player(&connection, &name, &owner).await
            })
            .await
        });
    }
    let mut players = vec![];
    while let Some(result) = reads.join_next().await {
        if let Ok(Ok(Ok(player))) = result {
            players.push(player);
        }
    }
    Ok((players, names))
}

async fn owner(connection: &zbus::Connection, name: &str) -> zbus::Result<String> {
    let dbus = zbus::fdo::DBusProxy::new(connection).await?;
    Ok(dbus
        .get_name_owner(BusName::try_from(name)?)
        .await?
        .to_string())
}

async fn read_player(
    connection: &zbus::Connection,
    name: &str,
    owner: &str,
) -> zbus::Result<MediaPlayerSnapshot> {
    let proxy =
        zbus::Proxy::new(connection, owner, PATH, "org.freedesktop.DBus.Properties").await?;
    let properties: Properties = proxy.call("GetAll", &(PLAYER,)).await?;
    let root: Properties = proxy.call("GetAll", &("org.mpris.MediaPlayer2",)).await?;
    let metadata = properties
        .get("Metadata")
        .and_then(|v| v.try_clone().ok())
        .and_then(|v| Properties::try_from(v).ok())
        .unwrap_or_default();
    let artist = metadata
        .get("xesam:artist")
        .and_then(|v| v.try_clone().ok())
        .and_then(|v| Vec::<String>::try_from(v).ok())
        .unwrap_or_default()
        .join(", ");
    let length_seconds = integer(&metadata, "mpris:length")
        .filter(|length| *length > 0)
        .map(|length| length as f64 / 1e6);
    let can_control = boolean(&properties, "CanControl");
    let seek_token = if can_control && boolean(&properties, "CanSeek") && length_seconds.is_some() {
        metadata
            .get("mpris:trackid")
            .and_then(|value| <&ObjectPath>::try_from(value).ok())
            .filter(|path| path.as_str() != "/org/mpris/MediaPlayer2/TrackList/NoTrack")
            .map(|path| format!("{owner}{path}"))
    } else {
        None
    };
    Ok(MediaPlayerSnapshot {
        bus_name: name.into(),
        identity: string(&root, "Identity"),
        title: string(&metadata, "xesam:title"),
        artist,
        album: string(&metadata, "xesam:album"),
        art_url: string(&metadata, "mpris:artUrl"),
        playback_status: string(&properties, "PlaybackStatus"),
        can_control,
        can_go_next: boolean(&properties, "CanGoNext"),
        can_go_previous: boolean(&properties, "CanGoPrevious"),
        can_play: boolean(&properties, "CanPlay"),
        can_pause: boolean(&properties, "CanPause"),
        position_seconds: integer(&properties, "Position").map(|v| v as f64 / 1e6),
        length_seconds,
        seek_token,
    })
}

fn string(values: &Properties, key: &str) -> String {
    values
        .get(key)
        .and_then(|v| <&str>::try_from(v).ok())
        .unwrap_or_default()
        .into()
}
fn boolean(values: &Properties, key: &str) -> bool {
    values
        .get(key)
        .and_then(|v| bool::try_from(v).ok())
        .unwrap_or(false)
}
fn integer(values: &Properties, key: &str) -> Option<i64> {
    values
        .get(key)
        .and_then(|v| i64::try_from(v).ok())
        .filter(|v| *v >= 0)
}

pub(crate) async fn action(
    name: &str,
    action: &str,
    seek: Option<(&str, f64)>,
) -> Result<(), String> {
    if !is_player(name) || BusName::try_from(name).is_err() {
        return Err("Invalid MPRIS player".into());
    }
    match (action, seek) {
        ("seek", Some((_, seconds))) if seconds.is_finite() && seconds >= 0.0 => {}
        ("previous" | "next" | "playPause" | "select", None) => {}
        _ => return Err("Invalid media action".into()),
    }
    let mut state = state().lock().await;
    tokio::time::timeout(Duration::from_secs(2), async {
        let connection = zbus::Connection::session()
            .await
            .map_err(|e| e.to_string())?;
        let owner = owner(&connection, name).await.map_err(|e| e.to_string())?;
        let player = read_player(&connection, name, &owner)
            .await
            .map_err(|e| e.to_string())?;
        if action == "select" {
            state.selected = Some(name.to_owned());
            return Ok(());
        }
        if !player.can_control {
            return Err("Player does not support control".into());
        }
        let proxy = zbus::Proxy::new(&connection, owner.as_str(), PATH, PLAYER)
            .await
            .map_err(|e| e.to_string())?;
        if let Some((track, seconds)) = seek {
            if player.seek_token.as_deref() != Some(track)
                || player.length_seconds.is_none_or(|length| seconds > length)
            {
                return Err("Track changed or position is unavailable".into());
            }
            let path = track.strip_prefix(&owner).ok_or("Invalid track owner")?;
            let path = ObjectPath::try_from(path).map_err(|e| e.to_string())?;
            return proxy
                .call::<_, _, ()>("SetPosition", &(path, (seconds * 1e6).round() as i64))
                .await
                .map_err(|e| e.to_string());
        }
        let method = match action {
            "previous" if player.can_go_previous => "Previous",
            "next" if player.can_go_next => "Next",
            "playPause" if player.playback_status == "Playing" && player.can_pause => "Pause",
            "playPause" if player.playback_status != "Playing" && player.can_play => "Play",
            _ => return Err("Player does not support this action".into()),
        };
        proxy
            .call::<_, _, ()>(method, &())
            .await
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|_| "MPRIS action timed out".to_string())??;
    state.updated = None;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn actions_reject_unknown_targets_and_operations_before_connecting() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        runtime.block_on(async {
            assert!(
                action("org.other.Service", "playPause", None)
                    .await
                    .is_err()
            );
            assert!(
                action("org.mpris.MediaPlayer2.example", "Delete", None)
                    .await
                    .is_err()
            );
        });
    }

    #[test]
    fn absent_or_invalid_metadata_remains_empty() {
        let mut values = Properties::new();
        values.insert("Position".into(), OwnedValue::from(-1_i64));
        values.insert("CanPlay".into(), OwnedValue::from(true));
        assert!(boolean(&values, "CanPlay"));
        assert!(!boolean(&values, "CanControl"));
        assert_eq!(integer(&values, "Position"), None);
        assert_eq!(string(&values, "xesam:title"), "");
    }
}
