use std::time::Duration;
use zbus::{Connection, Proxy};

pub async fn action(action: &str) -> Result<(), String> {
    let method = match action {
        "lock" => "LockSession",
        "logout" => "TerminateSession",
        "restart" => "Reboot",
        "shutdown" => "PowerOff",
        _ => return Err("Unknown session action".into()),
    };
    tokio::time::timeout(Duration::from_secs(30), async {
        let connection = Connection::system().await?;
        let manager = Proxy::new(
            &connection,
            "org.freedesktop.login1",
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
        )
        .await?;
        if matches!(action, "lock" | "logout") {
            // logind resolves the caller's own graphical session.
            let session = std::env::var("XDG_SESSION_ID").unwrap_or_default();
            manager.call::<_, _, ()>(method, &(session,)).await
        } else {
            manager.call::<_, _, ()>(method, &(true,)).await
        }
    })
    .await
    .map_err(|_| "Session action timed out".to_owned())?
    .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    #[test]
    fn rejects_unknown_action_before_contacting_logind() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        assert_eq!(
            runtime.block_on(super::action("suspend")).unwrap_err(),
            "Unknown session action"
        );
    }
}
