//! Run under `dbus-run-session -- cargo run -p remya_bar_system --example tray_smoke`.
use remya_bar_system::api::{tray_action, tray_items, tray_menu, tray_menu_action};
use std::collections::HashMap;
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicI32, Ordering},
};
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

struct Item(Arc<AtomicI32>);
#[zbus::interface(name = "org.kde.StatusNotifierItem")]
impl Item {
    #[zbus(property)]
    fn id(&self) -> &str {
        "remya-tray-smoke"
    }
    #[zbus(property)]
    fn title(&self) -> &str {
        "Tray transport test"
    }
    #[zbus(property)]
    fn status(&self) -> &str {
        "Active"
    }
    #[zbus(property)]
    fn icon_name(&self) -> &str {
        "dialog-information"
    }
    #[zbus(property)]
    fn icon_pixmap(&self) -> Vec<(i32, i32, Vec<u8>)> {
        vec![(1, 1, vec![255, 10, 20, 30])]
    }
    #[zbus(property)]
    fn item_is_menu(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn menu(&self) -> OwnedObjectPath {
        "/Menu".try_into().unwrap()
    }
    fn activate(&self, _x: i32, _y: i32) {
        self.0.fetch_add(1, Ordering::SeqCst);
    }
    fn secondary_activate(&self, _x: i32, _y: i32) {
        self.0.fetch_add(10, Ordering::SeqCst);
    }
    fn scroll(&self, delta: i32, _orientation: &str) {
        self.0.fetch_add(delta, Ordering::SeqCst);
    }
}
type Layout = (i32, HashMap<String, OwnedValue>, Vec<OwnedValue>);
struct Menu(Arc<AtomicI32>, AtomicBool);
#[zbus::interface(name = "com.canonical.dbusmenu")]
impl Menu {
    fn about_to_show(&self, id: i32) -> bool {
        if id == 42 {
            self.1.store(true, Ordering::SeqCst);
        }
        true
    }
    fn get_layout(&self, parent: i32, depth: i32, _properties: Vec<String>) -> (u32, Layout) {
        assert_eq!(depth, 1);
        let children = match parent {
            0 => Some((42, "_Options", "submenu")),
            42 if self.1.load(Ordering::SeqCst) => Some((43, "_Open", "")),
            _ => None,
        };
        let children = children
            .into_iter()
            .map(|(id, label, display)| {
                let properties: HashMap<String, OwnedValue> = [
                    ("label".into(), zbus::zvariant::Str::from(label).into()),
                    (
                        "children-display".into(),
                        zbus::zvariant::Str::from(display).into(),
                    ),
                ]
                .into();
                OwnedValue::try_from(Value::from((id, properties, Vec::<OwnedValue>::new())))
                    .unwrap()
            })
            .collect();
        (1, (parent, HashMap::new(), children))
    }
    fn event(&self, id: i32, event: &str, _data: OwnedValue, _time: u32) {
        assert_eq!(event, "clicked");
        self.0.fetch_add(id, Ordering::SeqCst);
    }
}
fn main() {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            assert!(tray_items().await.unwrap().is_empty());
            let count = Arc::new(AtomicI32::new(0));
            let connection = zbus::connection::Builder::session()
                .unwrap()
                .serve_at("/StatusNotifierItem", Item(count.clone()))
                .unwrap()
                .serve_at("/Menu", Menu(count.clone(), AtomicBool::new(false)))
                .unwrap()
                .build()
                .await
                .unwrap();
            let watcher = zbus::Proxy::new(
                &connection,
                "org.kde.StatusNotifierWatcher",
                "/StatusNotifierWatcher",
                "org.kde.StatusNotifierWatcher",
            )
            .await
            .unwrap();
            watcher
                .call::<_, _, ()>("RegisterStatusNotifierItem", &("/StatusNotifierItem",))
                .await
                .unwrap();
            tokio::time::sleep(std::time::Duration::from_millis(800)).await;
            let items = tray_items().await.unwrap();
            assert_eq!(items.len(), 1);
            let item = &items[0];
            assert_eq!(item.title, "Tray transport test");
            assert_eq!(item.icon_argb, vec![255, 10, 20, 30]);
            assert!(item.has_menu);
            tray_action(item.id.clone(), "activate".into(), 0)
                .await
                .unwrap();
            tray_action(item.id.clone(), "secondary".into(), 0)
                .await
                .unwrap();
            tray_action(item.id.clone(), "scroll".into(), 120)
                .await
                .unwrap();
            let menu = tray_menu(item.id.clone(), 0).await.unwrap();
            assert!(item.app_id.ends_with("/remya-tray-smoke"));
            assert_eq!(menu[0].label, "Options");
            assert!(menu[0].submenu);
            assert!(tray_menu_action(item.id.clone(), 0, 42).await.is_err());
            let submenu = tray_menu(item.id.clone(), 42).await.unwrap();
            assert_eq!(submenu[0].label, "Open");
            tray_menu_action(item.id.clone(), 42, 43).await.unwrap();
            assert_eq!(count.load(Ordering::SeqCst), 174);
            assert!(tray_menu_action(item.id.clone(), 0, 999).await.is_err());
            drop(watcher);
            drop(connection);
            tokio::time::sleep(std::time::Duration::from_millis(800)).await;
            assert!(tray_items().await.unwrap().is_empty());
            println!("SNI registration, pixmap, actions, menu dispatch and removal passed");
        });
}
