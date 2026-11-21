use std::collections::BTreeSet;
use std::sync::Arc;

use super::target;

#[derive(Clone, Default)]
pub(super) struct Watcher {
    pub(super) items: Arc<tokio::sync::Mutex<BTreeSet<String>>>,
}

#[zbus::interface(name = "org.kde.StatusNotifierWatcher")]
impl Watcher {
    async fn register_status_notifier_item(
        &self,
        service: String,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        let sender = header
            .sender()
            .ok_or_else(|| zbus::fdo::Error::InvalidArgs("Missing sender".into()))?;
        let id = if service.starts_with('/') {
            format!("{sender}{service}")
        } else {
            let connection = emitter.connection();
            let dbus = zbus::fdo::DBusProxy::new(connection).await?;
            let name = zbus::names::BusName::try_from(service)
                .map_err(|error| zbus::fdo::Error::InvalidArgs(error.to_string()))?;
            if dbus.get_name_owner(name).await?.as_str() != sender.as_str() {
                return Err(zbus::fdo::Error::AccessDenied(
                    "Tray service belongs to another client".into(),
                ));
            }
            format!("{sender}/StatusNotifierItem")
        };
        target(&id).map_err(zbus::fdo::Error::InvalidArgs)?;
        if self.items.lock().await.insert(id.clone()) {
            Self::status_notifier_item_registered(&emitter, &id).await?;
        }
        Ok(())
    }

    async fn register_status_notifier_host(&self, _service: String) {}

    #[zbus(property)]
    async fn registered_status_notifier_items(&self) -> Vec<String> {
        self.items.lock().await.iter().cloned().collect()
    }
    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn protocol_version(&self) -> i32 {
        0
    }
    #[zbus(signal)]
    async fn status_notifier_item_registered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    pub(super) async fn status_notifier_item_unregistered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn status_notifier_host_registered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::Result<()>;
}
