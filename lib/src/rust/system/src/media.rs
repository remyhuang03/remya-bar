use crate::api::MediaPlayerSnapshot;
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::for_generated::futures::{FutureExt, StreamExt, future, stream};
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};
use tokio::sync::{Mutex, watch};
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

fn connections() -> &'static Mutex<Option<Arc<zbus::Connection>>> {
    static CONNECTION: OnceLock<Mutex<Option<Arc<zbus::Connection>>>> = OnceLock::new();
    CONNECTION.get_or_init(Default::default)
}

async fn connection() -> zbus::Result<Arc<zbus::Connection>> {
    let mut cached = connections().lock().await;
    if cached.is_none() {
        *cached = Some(Arc::new(zbus::Connection::session().await?));
    }
    Ok(cached.as_ref().unwrap().clone())
}

async fn reset_connection(connection: &Arc<zbus::Connection>) {
    let mut cached = connections().lock().await;
    if cached
        .as_ref()
        .is_some_and(|current| Arc::ptr_eq(current, connection))
    {
        *cached = None;
    }
}

fn connection_error(error: &zbus::Error) -> bool {
    match error {
        zbus::Error::InputOutput(_) | zbus::Error::Handshake(_) => true,
        zbus::Error::FDO(error) => match error.as_ref() {
            zbus::fdo::Error::ZBus(error) => connection_error(error),
            zbus::fdo::Error::Disconnected(_) | zbus::fdo::Error::IOError(_) => true,
            _ => false,
        },
        zbus::Error::MethodError(name, _, _) => {
            name.as_str() == "org.freedesktop.DBus.Error.Disconnected"
        }
        _ => false,
    }
}

async fn checked<T>(
    connection: &Arc<zbus::Connection>,
    result: zbus::Result<T>,
) -> Result<T, String> {
    if let Err(error) = &result
        && connection_error(error)
    {
        reset_connection(connection).await;
    }
    result.map_err(|error| error.to_string())
}

fn invalidations() -> &'static watch::Sender<()> {
    static INVALIDATIONS: OnceLock<watch::Sender<()>> = OnceLock::new();
    INVALIDATIONS.get_or_init(|| watch::channel(()).0)
}

pub(crate) async fn players() -> Result<Vec<MediaPlayerSnapshot>, String> {
    read_players(false).await
}

async fn read_players(fresh: bool) -> Result<Vec<MediaPlayerSnapshot>, String> {
    let mut state = state().lock().await;
    if !fresh
        && state
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
    let connection = connection().await.map_err(|e| e.to_string())?;
    let names = checked(
        &connection,
        async {
            zbus::fdo::DBusProxy::new(&connection)
                .await?
                .list_names()
                .await
                .map_err(Into::into)
        }
        .await,
    )
    .await?;
    let names: Vec<_> = names
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
        match result {
            Ok(Ok(Ok(player))) => players.push(player),
            Ok(Ok(Err(error))) if connection_error(&error) => {
                return checked(&connection, Err(error)).await;
            }
            _ => {}
        }
    }
    Ok((players, names))
}

pub(crate) async fn subscribe(sink: StreamSink<Vec<MediaPlayerSnapshot>>) {
    let mut backoff = 1;
    loop {
        match watch_players(&sink, &mut backoff).await {
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

async fn watch_players(
    sink: &StreamSink<Vec<MediaPlayerSnapshot>>,
    backoff: &mut u64,
) -> Result<(), String> {
    let connection = tokio::time::timeout(Duration::from_secs(2), connection())
        .await
        .map_err(|_| "MPRIS connection timed out".to_string())?
        .map_err(|error| error.to_string())?;
    let result = watch_connection(sink, &connection, backoff).await;
    if result.is_err() {
        reset_connection(&connection).await;
    }
    result
}

async fn watch_connection(
    sink: &StreamSink<Vec<MediaPlayerSnapshot>>,
    connection: &Arc<zbus::Connection>,
    backoff: &mut u64,
) -> Result<(), String> {
    let rules = [
        zbus::MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .interface("org.freedesktop.DBus.Properties")
            .unwrap()
            .member("PropertiesChanged")
            .unwrap()
            .path(PATH)
            .unwrap()
            .build(),
        zbus::MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .interface(PLAYER)
            .unwrap()
            .member("Seeked")
            .unwrap()
            .path(PATH)
            .unwrap()
            .build(),
        zbus::MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .sender("org.freedesktop.DBus")
            .unwrap()
            .interface("org.freedesktop.DBus")
            .unwrap()
            .member("NameOwnerChanged")
            .unwrap()
            .arg0ns("org.mpris.MediaPlayer2")
            .unwrap()
            .build(),
    ];
    let mut streams = Vec::new();
    for rule in rules {
        let messages = tokio::time::timeout(
            Duration::from_secs(2),
            zbus::MessageStream::for_match_rule(rule, connection, Some(64)),
        )
        .await
        .map_err(|_| "MPRIS subscription timed out".to_string())?
        .map_err(|error| error.to_string())?;
        streams.push(messages);
    }
    let mut signals = stream::select_all(streams);
    let mut changes = invalidations().subscribe();
    let mut previous = None;
    loop {
        let players = read_players(true).await?;
        *backoff = 1;
        let playing = players
            .iter()
            .any(|player| player.playback_status == "Playing");
        if replace_changed(&mut previous, players)
            && sink.add(previous.as_ref().unwrap().clone()).is_err()
        {
            return Ok(());
        }
        let signal = async {
            match future::select(Box::pin(signals.next()), Box::pin(changes.changed())).await {
                future::Either::Left((Some(Ok(_)), _)) | future::Either::Right((Ok(()), _)) => {
                    Ok(())
                }
                future::Either::Left((Some(Err(error)), _)) => Err(error.to_string()),
                _ => Err("MPRIS signal stream closed".into()),
            }
        };
        if playing {
            if let Ok(result) = tokio::time::timeout(Duration::from_secs(1), signal).await {
                result?;
            }
        } else {
            signal.await?;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
        loop {
            match signals.next().now_or_never() {
                Some(Some(Ok(_))) => {}
                Some(Some(Err(error))) => return Err(error.to_string()),
                Some(None) => return Err("MPRIS signal stream closed".into()),
                None => break,
            }
        }
    }
}

fn replace_changed(
    previous: &mut Option<Vec<MediaPlayerSnapshot>>,
    next: Vec<MediaPlayerSnapshot>,
) -> bool {
    if previous.as_ref() == Some(&next) {
        return false;
    }
    *previous = Some(next);
    true
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
        let connection = connection().await.map_err(|e| e.to_string())?;
        let owner = checked(&connection, owner(&connection, name).await).await?;
        let player = checked(&connection, read_player(&connection, name, &owner).await).await?;
        if action == "select" {
            state.selected = Some(name.to_owned());
            return Ok(());
        }
        if !player.can_control {
            return Err("Player does not support control".into());
        }
        let proxy = checked(
            &connection,
            zbus::Proxy::new(&connection, owner.as_str(), PATH, PLAYER).await,
        )
        .await?;
        if let Some((track, seconds)) = seek {
            if player.seek_token.as_deref() != Some(track)
                || player.length_seconds.is_none_or(|length| seconds > length)
            {
                return Err("Track changed or position is unavailable".into());
            }
            let path = track.strip_prefix(&owner).ok_or("Invalid track owner")?;
            let path = ObjectPath::try_from(path).map_err(|e| e.to_string())?;
            return checked(
                &connection,
                proxy
                    .call::<_, _, ()>("SetPosition", &(path, (seconds * 1e6).round() as i64))
                    .await,
            )
            .await;
        }
        let method = match action {
            "previous" if player.can_go_previous => "Previous",
            "next" if player.can_go_next => "Next",
            "playPause" if player.playback_status == "Playing" && player.can_pause => "Pause",
            "playPause" if player.playback_status != "Playing" && player.can_play => "Play",
            _ => return Err("Player does not support this action".into()),
        };
        checked(&connection, proxy.call::<_, _, ()>(method, &()).await).await
    })
    .await
    .map_err(|_| "MPRIS action timed out".to_string())??;
    state.updated = None;
    invalidations().send_replace(());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_transport_failures_reset_the_connection() {
        assert!(connection_error(&zbus::Error::InputOutput(Arc::new(
            std::io::Error::from(std::io::ErrorKind::BrokenPipe)
        ))));
        assert!(connection_error(&zbus::Error::FDO(Box::new(
            zbus::fdo::Error::Disconnected("closed".into())
        ))));
        assert!(!connection_error(&zbus::Error::FDO(Box::new(
            zbus::fdo::Error::NameHasNoOwner("player exited".into())
        ))));
    }

    #[test]
    fn snapshots_emit_initial_and_changes_only() {
        let mut previous = None;
        assert!(replace_changed(&mut previous, vec![]));
        assert!(!replace_changed(&mut previous, vec![]));
        let player = MediaPlayerSnapshot {
            bus_name: "test".into(),
            identity: String::new(),
            title: String::new(),
            artist: String::new(),
            album: String::new(),
            art_url: String::new(),
            playback_status: "Paused".into(),
            can_control: true,
            can_go_next: false,
            can_go_previous: false,
            can_play: true,
            can_pause: true,
            seek_token: None,
            position_seconds: Some(0.0),
            length_seconds: Some(10.0),
        };
        assert!(replace_changed(&mut previous, vec![player.clone()]));
        assert!(!replace_changed(&mut previous, vec![player.clone()]));
        let mut playing = player;
        playing.playback_status = "Playing".into();
        assert!(replace_changed(&mut previous, vec![playing.clone()]));
        playing.position_seconds = Some(1.0);
        assert!(replace_changed(&mut previous, vec![playing]));
        assert!(replace_changed(&mut previous, vec![]));
    }

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
