use std::io::{self, ErrorKind};
use std::net::{Ipv4Addr, TcpListener};
use std::process::Stdio;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::Mutex;
use tokio::time::timeout;

static SERVER: Mutex<Option<(u16, Child)>> = Mutex::const_new(None);

fn command() -> Command {
    let mut command = Command::new("codexbar");
    command.stdin(Stdio::null()).kill_on_drop(true);
    let parent = std::process::id();
    // Flutter engines may disappear without disposing their Dart objects.
    // Tie the child to the bar process even when the bar is killed.
    unsafe {
        command.pre_exec(move || {
            if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) == -1 {
                return Err(io::Error::last_os_error());
            }
            if libc::getppid() as u32 != parent {
                return Err(ErrorKind::Interrupted.into());
            }
            Ok(())
        });
    }
    command
}

pub async fn server_port(token: &str) -> Option<i32> {
    let mut server = SERVER.lock().await;
    if let Some((port, child)) = server.as_mut()
        && matches!(child.try_wait(), Ok(None))
    {
        return Some(i32::from(*port));
    }
    *server = None;
    let reservation = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).ok()?;
    let port = reservation.local_addr().ok()?.port();
    drop(reservation);
    let mut child = command()
        .args([
            "serve",
            "--host",
            "127.0.0.1",
            "--port",
            &port.to_string(),
            "--refresh-interval",
            "300",
            "--request-timeout",
            "30",
            "--identity",
            "redacted",
        ])
        .env("CODEXBAR_DASHBOARD_TOKEN", token)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .ok()?;

    // Only connect once our child confirms the bind, since another process
    // could claim the port after the temporary reservation is released.
    let mut stderr = BufReader::new(child.stderr.take()?);
    let ready = format!("CodexBar server listening on http://127.0.0.1:{port}");
    timeout(Duration::from_secs(4), async {
        let mut line = String::new();
        while stderr.read_line(&mut line).await.ok()? != 0 {
            if line.trim() == ready {
                return Some(());
            }
            line.clear();
        }
        None
    })
    .await
    .ok()??;
    tokio::spawn(async move {
        let _ = tokio::io::copy(&mut stderr, &mut tokio::io::sink()).await;
    });
    *server = Some((port, child));
    Some(i32::from(port))
}

pub async fn json(kind: &str, refresh: bool) -> Result<Option<String>, String> {
    let mut command = command();
    match kind {
        "providers" => command.args(["config", "providers"]),
        "usage" => command.args(["usage", "--status"]),
        "cost" => {
            command.args(["cost", "--days", "30"]);
            if refresh {
                command.arg("--refresh");
            }
            &mut command
        }
        _ => return Err("Unknown CodexBar operation".into()),
    };
    let output = timeout(
        Duration::from_secs(40),
        command.args(["--format", "json"]).output(),
    )
    .await
    .map_err(|_| "CodexBar request timed out")?;
    match output {
        // Partial provider results can accompany a nonzero exit code.
        Ok(result) if !result.stdout.is_empty() => String::from_utf8(result.stdout)
            .map(Some)
            .map_err(|_| "Invalid CodexBar response".into()),
        Ok(_) => Err("CodexBar returned no data".into()),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.to_string()),
    }
}

pub async fn notify(provider: &str, window: &str, threshold: i32) {
    let send = async {
        let connection = zbus::Connection::session().await?;
        let notifications = zbus::Proxy::new(
            &connection,
            "org.freedesktop.Notifications",
            "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications",
        )
        .await?;
        let summary = if threshold == 0 {
            "AI quota exhausted"
        } else {
            "AI quota low"
        };
        let body = format!("{provider} · {window} · {threshold}% threshold reached");
        notifications
            .call::<_, _, u32>(
                "Notify",
                &(
                    "Remy'a Bar",
                    0_u32,
                    "top.remya.bar",
                    summary,
                    body,
                    Vec::<String>::new(),
                    std::collections::HashMap::<String, zbus::zvariant::Value>::new(),
                    -1_i32,
                ),
            )
            .await
    };
    let _ = timeout(Duration::from_secs(5), send).await;
}
