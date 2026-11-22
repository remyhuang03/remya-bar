use super::*;

#[test]
fn dbus_calls_wait_for_history_and_abort_if_startup_fails() {
    tokio::runtime::Builder::new_current_thread()
        .enable_time()
        .build()
        .unwrap()
        .block_on(async {
            let (ready, server) = watch::channel(false);
            let server = Server { ready: server };
            assert!(
                tokio::time::timeout(Duration::ZERO, server.wait_until_ready())
                    .await
                    .is_err()
            );
            ready.send_replace(true);
            drop(ready);
            assert!(server.wait_until_ready().await.is_ok());

            let (ready, server) = watch::channel(false);
            drop(ready);
            assert!(Server { ready: server }.wait_until_ready().await.is_err());
        });
}

#[test]
fn daemon_state_stays_available_while_dbus_ownership_is_pending() {
    tokio::runtime::Builder::new_current_thread()
        .enable_time()
        .build()
        .unwrap()
        .block_on(async {
            let claimed = std::sync::Arc::new(Notify::new());
            let claim_started = claimed.clone();
            let (finish, wait_for_test) = tokio::sync::oneshot::channel();
            let ownership = tokio::spawn(async move {
                start_server(async move |_| {
                    claim_started.notify_one();
                    wait_for_test.await.unwrap();
                    Err("D-Bus is unavailable".into())
                })
                .await
            });
            tokio::time::timeout(Duration::from_secs(1), async {
                claimed.notified().await;
                let preferences = Daemon::new().preferences;
                configure(preferences).await;
                fullscreen("test-output".into(), true).await;
                assert!(daemon().lock().await.fullscreen.contains("test-output"));
                finish.send(()).unwrap();
            })
            .await
            .unwrap();
            assert!(!ownership.await.unwrap());
        });
}

fn entry(id: u32, urgency: u8, transient: bool) -> Entry {
    Entry {
        order: i64::from(id),
        snapshot: NotificationSnapshot {
            id,
            app_name: String::new(),
            app_icon: String::new(),
            desktop_entry: String::new(),
            summary: String::new(),
            body: Vec::new(),
            actions: Vec::new(),
            default_action: false,
            urgency,
            received_unix_ms: 0,
            image_argb: Vec::new(),
            image_width: 0,
            image_height: 0,
            image_path: String::new(),
            progress: None,
            popup: false,
            popup_sequence: 0,
            transient,
            resident: false,
            category: String::new(),
        },
        timeout: Some(Duration::from_secs(1)),
        deadline: None,
        remaining: None,
    }
}

#[test]
fn history_survives_reopen_without_replaying_actions_or_transient_popups() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path();
    let (mut history, empty, next_id) = History::open(path).unwrap();
    assert!(empty.is_empty());
    assert_eq!(next_id, 1);
    assert!(
        History::open(path).is_err(),
        "one writer per state directory"
    );

    let mut older = entry(1, 1, false);
    older.snapshot.popup = true;
    older.snapshot.default_action = true;
    older.snapshot.resident = true;
    older.snapshot.body = parse_body("<b>Hello</b>");
    older.snapshot.image_width = 1;
    older.snapshot.image_height = 1;
    older.snapshot.image_argb = vec![255, 1, 2, 3];
    history.save(&[older], 2, Some(1), &[]).unwrap();
    history
        .save(&[entry(2, 1, false)], 3, Some(2), &[])
        .unwrap();
    history.save(&[entry(3, 1, true)], 4, Some(3), &[]).unwrap();
    drop(history);

    let (mut history, mut entries, next_id) = History::open(path).unwrap();
    assert_eq!(next_id, 4);
    assert_eq!(
        entries
            .iter()
            .map(|entry| entry.snapshot.id)
            .collect::<Vec<_>>(),
        [2, 1]
    );
    let restored = &entries[1].snapshot;
    assert!(!restored.popup && !restored.default_action);
    assert!(restored.resident);
    assert!(restored.body[0].bold);
    assert_eq!(restored.image_argb, [255, 1, 2, 3]);
    entries[1].snapshot.summary = "Updated".into();
    history.save(&entries, 4, Some(1), &[]).unwrap();
    drop(history);

    let (mut history, entries, _) = History::open(path).unwrap();
    assert_eq!(
        entries[1].snapshot.summary, "Updated",
        "replacement keeps its place"
    );
    history.save(&[], 4, None, &[1, 2]).unwrap();
    drop(history);
    let (_, empty, next_id) = History::open(path).unwrap();
    assert!(empty.is_empty(), "Clear all survives restart");
    assert_eq!(next_id, 4, "Clearing history does not recycle IDs");
}

#[test]
fn failed_history_transaction_rolls_back_and_retries_current_state() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path();
    let (mut history, _, _) = History::open(path).unwrap();
    history
        .save(&[entry(1, 1, false)], 2, Some(1), &[])
        .unwrap();
    let db = rusqlite::Connection::open(path.join("notifications.sqlite3")).unwrap();
    db.execute_batch(
        "CREATE TRIGGER fail_insert BEFORE INSERT ON history
         BEGIN SELECT RAISE(ABORT, 'test write failure'); END;",
    )
    .unwrap();
    let entries = [entry(2, 1, false)];
    assert!(history.save(&entries, 3, Some(2), &[1]).is_err());
    assert_eq!(
        db.query_row("SELECT id FROM history", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        1
    );
    db.execute_batch("DROP TRIGGER fail_insert;").unwrap();
    history.save(&entries, 3, None, &[]).unwrap();
    drop(history);
    let (_, restored, next_id) = History::open(path).unwrap();
    assert_eq!(restored[0].snapshot.id, 2);
    assert_eq!(next_id, 3);
}

#[test]
fn popups_expire_pause_and_respect_do_not_disturb() {
    let mut daemon = Daemon::new();
    daemon.entries = vec![entry(1, 1, false), entry(2, 1, true), entry(3, 2, false)];
    for index in 0..3 {
        daemon.update_popup(index, true);
    }
    assert!(daemon.entries.iter().all(|entry| entry.snapshot.popup));
    assert!(
        daemon.entries[2].deadline.is_none(),
        "critical never expires"
    );
    daemon.set_hovered(true);
    assert!(
        daemon
            .expire(Instant::now() + Duration::from_secs(5))
            .is_empty()
    );
    daemon.set_hovered(false);
    assert_eq!(
        daemon.expire(Instant::now() + Duration::from_secs(5)),
        vec![2]
    );
    assert_eq!(daemon.entries.len(), 2, "transient leaves history");
    assert!(!daemon.entries[0].snapshot.popup);

    daemon.preferences.do_not_disturb = true;
    daemon.refresh_quiet(now());
    daemon.update_popup(0, true);
    daemon.update_popup(1, true);
    assert!(!daemon.entries[0].snapshot.popup);
    assert!(daemon.entries[1].snapshot.popup, "critical bypasses DND");
}

#[test]
fn silent_delivery_is_filtered_and_positive_timeouts_have_a_minimum() {
    let mut daemon = Daemon::new();
    assert_eq!(daemon.timeout(-1), Some(Duration::from_secs(5)));
    assert_eq!(daemon.timeout(50), Some(Duration::from_secs(2)));
    assert_eq!(daemon.timeout(0), None);
    daemon.preferences.timeout_seconds = 600;
    assert_eq!(daemon.timeout(-1), Some(Duration::from_secs(600)));
    let mut low = entry(1, 0, false);
    low.snapshot.category = "call.incoming".into();
    daemon.entries.push(low);
    daemon.update_popup(0, true);
    assert!(!daemon.entries[0].snapshot.popup);
    assert!(daemon.next_deadline().is_none());
}

#[test]
fn replacement_only_realerts_for_changed_titles_and_preserves_history_order() {
    let mut daemon = Daemon::new();
    let timeout = daemon.timeout(5000);
    let mut first = entry(0, 1, false).snapshot;
    first.summary = "Downloading".into();
    assert_eq!(daemon.receive(first.clone(), 0, timeout), (0, true));
    let id = daemon.entries[0].snapshot.id;
    let deadline = daemon.entries[0].deadline;
    let sequence = daemon.entries[0].snapshot.popup_sequence;
    daemon.receive(entry(0, 1, false).snapshot, 0, timeout);

    first.progress = Some(50);
    assert_eq!(daemon.receive(first.clone(), id, timeout), (1, false));
    assert_eq!(daemon.entries[1].deadline, deadline);
    assert_eq!(daemon.entries[1].snapshot.popup_sequence, sequence);
    assert_eq!(daemon.entries[1].snapshot.progress, Some(50));

    daemon.expire(Instant::now() + Duration::from_secs(6));
    first.progress = Some(99);
    assert_eq!(daemon.receive(first.clone(), id, timeout), (1, false));
    assert!(!daemon.entries[1].snapshot.popup);

    first.summary = "Downloaded".into();
    assert_eq!(daemon.receive(first, id, timeout), (1, false));
    assert!(daemon.entries[1].snapshot.popup);
    assert!(daemon.entries[1].snapshot.popup_sequence > daemon.entries[0].snapshot.popup_sequence);
}

#[test]
fn bulk_clear_filters_groups_and_sections_and_keeps_resident_entries() {
    let mut entries = vec![
        entry(1, 0, false),
        entry(2, 1, false),
        entry(3, 2, false),
        entry(4, 0, false),
        entry(5, 1, true),
    ];
    for entry in &mut entries {
        entry.snapshot.app_name = "Chat".into();
    }
    entries[0].snapshot.desktop_entry = "org.example.Chat".into();
    entries[3].snapshot.resident = true;
    assert_eq!(
        remove_matching(&mut entries, None, Some(0), Some("org.example.Chat"), true),
        [1]
    );
    assert_eq!(remove_matching(&mut entries, None, None, None, false), [2]);
    assert_eq!(remove_matching(&mut entries, None, None, None, true), [3]);
    assert_eq!(
        remove_matching(&mut entries, Some(4), None, None, false),
        [4]
    );
    assert_eq!(entries[0].snapshot.id, 5);
}

#[test]
fn resident_actions_end_the_alert_without_closing_history() {
    let mut daemon = Daemon::new();
    let mut resident = entry(1, 2, false);
    resident.snapshot.resident = true;
    resident.snapshot.default_action = true;
    daemon.entries.push(resident);
    daemon.update_popup(0, true);
    daemon.set_hovered(true);
    assert!(daemon.apply_action(1, "unknown").is_err());
    assert!(daemon.entries[0].snapshot.popup);
    assert!(!daemon.apply_action(1, "default").unwrap());
    assert_eq!(daemon.entries[0].snapshot.id, 1);
    assert!(!daemon.entries[0].snapshot.popup);
    release_host(&mut daemon);
    assert!(
        !daemon.hovered,
        "an emptied stack cannot pause later alerts"
    );
}

#[test]
fn one_output_hosts_popups_until_they_end() {
    let mut daemon = Daemon::new();
    assert!(!daemon.claim("DP-1".into()), "nothing to host");
    daemon.entries.push(entry(1, 1, false));
    daemon.update_popup(0, true);
    assert!(daemon.claim("DP-1".into()));
    assert!(!daemon.claim("DP-3".into()));
    assert!(daemon.claim("DP-1".into()));
    daemon.expire(Instant::now() + Duration::from_secs(5));
    release_host(&mut daemon);
    daemon.update_popup(0, true);
    assert!(
        daemon.claim("DP-3".into()),
        "an emptied stack frees the host"
    );
}

fn now() -> NaiveDateTime {
    at("2026-11-09 12:00") // A Monday.
}

fn at(time: &str) -> NaiveDateTime {
    NaiveDateTime::parse_from_str(time, "%Y-%m-%d %H:%M").unwrap()
}

#[test]
fn schedules_cross_midnight_from_their_start_day() {
    let mut preferences = Daemon::new().preferences;
    preferences.schedule_days = (1..=5).collect(); // Weekdays.
    assert!(
        scheduled(&preferences, at("2026-11-09 23:00")),
        "Monday night"
    );
    assert!(
        scheduled(&preferences, at("2026-11-10 06:59")),
        "Monday's period"
    );
    assert!(!scheduled(&preferences, at("2026-11-10 07:00")));
    assert!(!scheduled(&preferences, at("2026-11-14 23:00")), "Saturday");
    assert!(
        scheduled(&preferences, at("2026-11-14 06:00")),
        "Friday's period"
    );
    assert!(
        !scheduled(&preferences, at("2026-11-16 06:00")),
        "Sunday's period"
    );
    preferences.schedule_start_minutes = 9 * 60;
    preferences.schedule_end_minutes = 17 * 60;
    assert!(scheduled(&preferences, at("2026-11-09 12:00")));
    assert!(!scheduled(&preferences, at("2026-11-09 17:00")));
    preferences.schedule_end_minutes = 9 * 60;
    assert!(
        !scheduled(&preferences, at("2026-11-09 09:00")),
        "empty period"
    );
}

#[test]
fn quiet_reasons_and_priority_bypass() {
    let mut daemon = Daemon::new();
    daemon.preferences.fullscreen = true;
    daemon.fullscreen.insert("DP-1".into());
    let mut call = entry(1, 1, false);
    call.snapshot.category = "call.incoming".into();
    let mut chat = entry(2, 1, false);
    chat.snapshot.desktop_entry = "org.telegram.desktop".into();
    let mut named = entry(3, 1, false);
    named.snapshot.app_name = "Signal".into();
    daemon.entries = vec![call, chat, named, entry(4, 1, false)];
    for index in 0..4 {
        daemon.update_popup(index, true);
    }
    daemon.refresh_quiet(now());
    assert_eq!(daemon.quiet, Some("fullscreen"));
    daemon.preferences.priority_apps = vec![
        crate::api::NotificationPriorityApp {
            id: "ORG.TELEGRAM.DESKTOP".into(),
            name: "Telegram".into(),
        },
        crate::api::NotificationPriorityApp {
            id: "org.signal.Signal".into(),
            name: "signal".into(),
        },
    ];
    for index in 0..4 {
        daemon.update_popup(index, true);
    }
    let shown: Vec<_> = daemon
        .entries
        .iter()
        .map(|entry| entry.snapshot.popup)
        .collect();
    assert_eq!(shown, [true, true, true, false]);
    daemon.preferences.priority_calls = false;
    daemon.update_popup(0, true);
    assert!(!daemon.entries[0].snapshot.popup);
    daemon.fullscreen.clear();
    daemon.refresh_quiet(now());
    assert_eq!(daemon.quiet, None);
    daemon.preferences.do_not_disturb = true;
    daemon.preferences.schedule = true;
    daemon.preferences.schedule_start_minutes = 11 * 60;
    daemon.preferences.schedule_end_minutes = 13 * 60;
    daemon.refresh_quiet(now());
    assert_eq!(daemon.quiet, Some("manual"), "manual wins over schedule");
    assert_eq!(daemon.center().quiet_until_minutes, None);
    daemon.preferences.do_not_disturb = false;
    daemon.refresh_quiet(now());
    assert_eq!(daemon.center().quiet_until_minutes, Some(13 * 60));
}

#[test]
fn zero_timeout_never_expires() {
    let mut daemon = Daemon::new();
    let mut never = entry(1, 1, false);
    never.timeout = None;
    daemon.entries.push(never);
    daemon.update_popup(0, true);
    assert!(daemon.entries[0].snapshot.popup);
    assert!(daemon.entries[0].deadline.is_none());
}

#[test]
fn ids_start_at_one_and_skip_zero_and_live_ids() {
    let mut daemon = Daemon::new();
    assert_eq!(daemon.allocate_id(), 1);
    daemon.entries.push(entry(2, 1, false));
    assert_eq!(daemon.allocate_id(), 3);
    daemon.next_id = u32::MAX;
    assert_eq!(daemon.allocate_id(), u32::MAX);
    assert_eq!(daemon.allocate_id(), 1);
}

#[test]
fn next_schedule_boundary_finds_start_and_end_or_none_when_disabled() {
    let at = |s: &str| NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M:%S").unwrap();
    let mut preferences = NotificationPreferences {
        do_not_disturb: false,
        clear_critical: false,
        fullscreen: false,
        timeout_seconds: 5,
        sounds: true,
        schedule: false,
        schedule_start_minutes: 22 * 60,
        schedule_end_minutes: 7 * 60,
        schedule_days: vec![1, 5], // Monday and Friday.
        priority_calls: false,
        priority_apps: vec![],
    };
    assert_eq!(
        next_schedule_boundary(&preferences, at("2026-11-09 21:00:00")),
        None
    );

    preferences.schedule = true;
    // Monday 21:00 -> Monday 22:00 (1 hour).
    assert_eq!(
        next_schedule_boundary(&preferences, at("2026-11-09 21:00:00")),
        Some(Duration::from_secs(3600))
    );
    // Monday 23:30 -> Tuesday 07:00 (7.5 hours).
    assert_eq!(
        next_schedule_boundary(&preferences, at("2026-11-09 23:30:00")),
        Some(Duration::from_secs(7 * 3600 + 1800))
    );
    // Tuesday 07:00 (end of Monday's overnight period) -> Friday 22:00.
    assert_eq!(
        next_schedule_boundary(&preferences, at("2026-11-10 07:00:00")),
        Some(Duration::from_secs((3 * 24 + 15) * 3600))
    );
    // Equal start and end means no schedule boundaries.
    preferences.schedule_end_minutes = preferences.schedule_start_minutes;
    assert_eq!(
        next_schedule_boundary(&preferences, at("2026-11-09 21:00:00")),
        None
    );
}
