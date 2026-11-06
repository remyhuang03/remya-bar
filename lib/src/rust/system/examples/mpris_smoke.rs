//! Run with `dbus-run-session -- cargo run -p remya_bar_system --example mpris_smoke`.
//! Exercises the real MPRIS transport against an isolated test player.
use remya_bar_system::api::{media_action, media_players, media_seek};
use std::collections::HashMap;
use std::sync::{
    Arc,
    atomic::{AtomicU32, Ordering},
};
use zbus::zvariant::{ObjectPath, OwnedValue, Str, Value};

struct Identity;
#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl Identity {
    #[zbus(property)]
    fn identity(&self) -> &str {
        "Remya MPRIS transport test"
    }
}

struct Player(Arc<AtomicU32>, &'static str);
#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    fn previous(&self) {
        self.0.fetch_add(1, Ordering::SeqCst);
    }
    fn next(&self) {
        self.0.fetch_add(10, Ordering::SeqCst);
    }
    fn play(&self) {
        self.0.fetch_add(100, Ordering::SeqCst);
    }
    fn set_position(&self, track_id: ObjectPath<'_>, position: i64) {
        assert_eq!(track_id.as_str(), "/test/Track");
        assert_eq!(position, 7_500_000);
        self.0.fetch_add(1000, Ordering::SeqCst);
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn playback_status(&self) -> &str {
        self.1
    }
    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn position(&self) -> i64 {
        2_000_000
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> {
        HashMap::from([
            (
                "xesam:title".into(),
                OwnedValue::from(Str::from("Transport fixture")),
            ),
            ("mpris:length".into(), OwnedValue::from(12_000_000_i64)),
            (
                "mpris:trackid".into(),
                OwnedValue::try_from(Value::new(ObjectPath::try_from("/test/Track").unwrap()))
                    .unwrap(),
            ),
        ])
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async {
        let calls = Arc::new(AtomicU32::new(0));
        let name = "org.mpris.MediaPlayer2.remya_transport_test";
        let playing = "org.mpris.MediaPlayer2.playing_test";
        let _playing = zbus::connection::Builder::session()?
            .name(playing)?
            .serve_at("/org/mpris/MediaPlayer2", Identity)?
            .serve_at("/org/mpris/MediaPlayer2", Player(calls.clone(), "Playing"))?
            .build()
            .await?;
        let service = zbus::connection::Builder::session()?
            .name(name)?
            .serve_at("/org/mpris/MediaPlayer2", Identity)?
            .serve_at("/org/mpris/MediaPlayer2", Player(calls.clone(), "Paused"))?
            .build()
            .await?;
        let snapshot = media_players().await?;
        assert_eq!(snapshot[0].bus_name, playing);
        media_action(name.into(), "select".into()).await?;
        let snapshot = media_players().await?;
        let player = &snapshot[0];
        assert_eq!(player.bus_name, name);
        assert_eq!(player.title, "Transport fixture");
        assert_eq!(player.position_seconds, Some(2.0));
        assert_eq!(player.length_seconds, Some(12.0));
        for action in ["previous", "next", "playPause"] {
            media_action(name.into(), action.into()).await?;
        }
        let track = player.seek_token.clone().expect("seekable track");
        assert!(
            media_seek(name.into(), track.clone(), f64::NAN)
                .await
                .is_err()
        );
        assert!(media_seek(name.into(), track.clone(), 13.0).await.is_err());
        assert!(media_seek(name.into(), "/stale".into(), 7.5).await.is_err());
        media_seek(name.into(), track, 7.5).await?;
        assert_eq!(calls.load(Ordering::SeqCst), 1111);
        service.release_name(name).await?;
        assert_eq!(media_players().await?[0].bus_name, playing);
        println!("PASS: MPRIS discovery, player selection and fallback, transport, guarded seek");
        Ok(())
    })
}
