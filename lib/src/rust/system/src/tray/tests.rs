use super::*;
use zbus::zvariant::Value;

#[test]
fn validates_targets_and_pixmap_bounds() {
    assert!(target(":1.42/StatusNotifierItem").is_ok());
    assert!(target("not a bus/Item").is_err());
    assert!(target("org.example.App").is_err());
    let mut values = Properties::new();
    values.insert(
        "IconPixmap".into(),
        OwnedValue::try_from(Value::from(vec![(1_i32, 1_i32, vec![255_u8, 10, 20, 30])])).unwrap(),
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
    assert_eq!(menu::menu_label("_Open __ File"), "Open _ File");
    let entries = menu::menu_entries((
        0,
        Properties::new(),
        vec![OwnedValue::try_from(child).unwrap()],
    ));
    assert_eq!(entries[0].label, "Open");
    assert!(!entries[0].enabled);
    assert_eq!(entries[0].toggle_state, 1);
}

fn test_item(id: &str, app_id: &str, title: &str, icon_argb: Vec<u8>) -> TrayItem {
    TrayItem {
        id: id.into(),
        app_id: app_id.into(),
        icon_theme_path: String::new(),
        title: title.into(),
        icon_name: "test-icon".into(),
        icon_argb,
        icon_width: 1,
        icon_height: 1,
        item_is_menu: false,
        has_menu: false,
        attention: false,
    }
}

#[test]
fn maps_signal_sender_and_path_to_registered_ids() {
    let mut tracker = ItemTracker::default();
    tracker.upsert(
        ":1.42/StatusNotifierItem".into(),
        TrackedEntry {
            bus_name: ":1.42".into(),
            owner: ":1.42".into(),
            path: "/StatusNotifierItem".into(),
            item: Some(test_item(
                ":1.42/StatusNotifierItem",
                "app/a",
                "Alpha",
                vec![1, 2, 3, 4],
            )),
        },
    );
    tracker.upsert(
        ":1.42/SecondaryItem".into(),
        TrackedEntry {
            bus_name: ":1.42".into(),
            owner: ":1.42".into(),
            path: "/SecondaryItem".into(),
            item: None,
        },
    );
    tracker.upsert(
        "org.example.Tray/org/ayatana/NotificationItem/demo/Menu".into(),
        TrackedEntry {
            bus_name: "org.example.Tray".into(),
            owner: ":1.88".into(),
            path: "/org/ayatana/NotificationItem/demo/Menu".into(),
            item: Some(test_item(
                "org.example.Tray/org/ayatana/NotificationItem/demo/Menu",
                "demo",
                "Demo",
                vec![],
            )),
        },
    );

    let mut plan = RefreshPlan::default();
    assert!(record_tray_signal(
        &tracker,
        TraySignal::ItemPropertyChanged {
            sender: ":1.42",
            path: "/StatusNotifierItem",
        },
        &mut plan,
    ));
    assert!(!plan.refresh_ids);
    assert_eq!(
        plan.dirty_ids,
        BTreeSet::from([":1.42/StatusNotifierItem".into()])
    );

    // Passive item on the same sender at a distinct path wakes up on NewStatus.
    let mut passive_plan = RefreshPlan::default();
    assert!(record_tray_signal(
        &tracker,
        TraySignal::ItemPropertyChanged {
            sender: ":1.42",
            path: "/SecondaryItem",
        },
        &mut passive_plan,
    ));
    assert_eq!(
        passive_plan.dirty_ids,
        BTreeSet::from([":1.42/SecondaryItem".into()])
    );

    // Well-known name registration maps back from unique sender + object path.
    let mut wk_plan = RefreshPlan::default();
    assert!(record_tray_signal(
        &tracker,
        TraySignal::ItemPropertyChanged {
            sender: ":1.88",
            path: "/org/ayatana/NotificationItem/demo/Menu",
        },
        &mut wk_plan,
    ));
    assert_eq!(
        wk_plan.dirty_ids,
        BTreeSet::from(["org.example.Tray/org/ayatana/NotificationItem/demo/Menu".into()])
    );

    // Unrelated sender/path is ignored.
    let mut ignored = RefreshPlan::default();
    assert!(!record_tray_signal(
        &tracker,
        TraySignal::ItemPropertyChanged {
            sender: ":1.42",
            path: "/Other",
        },
        &mut ignored,
    ));
    assert!(ignored == RefreshPlan::default());
}

#[test]
fn watcher_and_owner_signals_update_refresh_plan() {
    let mut tracker = ItemTracker::default();
    tracker.upsert(
        "org.example.Tray/StatusNotifierItem".into(),
        TrackedEntry {
            bus_name: "org.example.Tray".into(),
            owner: ":1.88".into(),
            path: "/StatusNotifierItem".into(),
            item: None,
        },
    );

    let mut unrelated_owner = RefreshPlan::default();
    assert!(!record_tray_signal(
        &tracker,
        TraySignal::NameOwnerChanged {
            name: ":1.999",
            old_owner: ":1.999",
        },
        &mut unrelated_owner,
    ));

    let mut owner_vanished = RefreshPlan::default();
    assert!(record_tray_signal(
        &tracker,
        TraySignal::NameOwnerChanged {
            name: ":1.88",
            old_owner: ":1.88",
        },
        &mut owner_vanished,
    ));
    assert!(owner_vanished.refresh_ids);
    assert_eq!(
        owner_vanished.dirty_ids,
        BTreeSet::from(["org.example.Tray/StatusNotifierItem".into()])
    );

    let mut watcher_changed = RefreshPlan::default();
    assert!(record_tray_signal(
        &tracker,
        TraySignal::NameOwnerChanged {
            name: WATCHER,
            old_owner: ":1.5",
        },
        &mut watcher_changed,
    ));
    assert!(watcher_changed.full_resync);

    let mut registered_plan = RefreshPlan::default();
    assert!(record_tray_signal(
        &tracker,
        TraySignal::WatcherRegistered {
            service: Some(":1.77"),
        },
        &mut registered_plan,
    ));
    assert!(registered_plan.refresh_ids);
    assert_eq!(
        registered_plan.dirty_ids,
        BTreeSet::from([":1.77/StatusNotifierItem".into()])
    );

    let mut unregistered_plan = RefreshPlan::default();
    assert!(record_tray_signal(
        &tracker,
        TraySignal::WatcherUnregistered,
        &mut unregistered_plan,
    ));
    assert!(unregistered_plan.refresh_ids);
}

#[test]
fn snapshots_emit_initial_and_field_or_pixmap_changes_only() {
    let mut previous = None;
    assert!(replace_changed(&mut previous, vec![]));
    assert!(!replace_changed(&mut previous, vec![]));

    let item = test_item(":1.1/StatusNotifierItem", "app", "App", vec![1, 2, 3, 4]);
    assert!(replace_changed(&mut previous, vec![item.clone()]));
    assert!(!replace_changed(&mut previous, vec![item.clone()]));

    let mut title_changed = item.clone();
    title_changed.title = "Updated".into();
    assert!(replace_changed(&mut previous, vec![title_changed.clone()]));
    assert!(!replace_changed(&mut previous, vec![title_changed.clone()]));

    let mut pixmap_changed = title_changed;
    pixmap_changed.icon_argb = vec![9, 2, 3, 4];
    assert!(replace_changed(&mut previous, vec![pixmap_changed]));
    assert!(replace_changed(&mut previous, vec![]));
}
