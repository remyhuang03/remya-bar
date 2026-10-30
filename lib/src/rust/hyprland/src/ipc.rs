use crate::api::HyprlandUpdate;
use std::env;
use std::io::{self, ErrorKind};
use std::path::{Component, Path, PathBuf};
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;
use tokio::sync::{broadcast, watch};

const MAX_REPLY: u64 = 8 * 1024 * 1024;
const MAX_EVENT: u64 = 64 * 1024;

fn directory(runtime: &Path, signature: &str) -> io::Result<PathBuf> {
    let mut components = Path::new(signature).components();
    if !runtime.is_absolute()
        || !matches!(components.next(), Some(Component::Normal(_)))
        || components.next().is_some()
    {
        return Err(io::Error::new(
            ErrorKind::InvalidInput,
            "Invalid Hyprland session environment",
        ));
    }
    Ok(runtime.join("hypr").join(signature))
}

pub fn socket_directory() -> io::Result<PathBuf> {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .ok_or_else(|| io::Error::new(ErrorKind::NotFound, "XDG_RUNTIME_DIR is missing"))?;
    let signature = env::var("HYPRLAND_INSTANCE_SIGNATURE").map_err(|_| {
        io::Error::new(
            ErrorKind::NotFound,
            "HYPRLAND_INSTANCE_SIGNATURE is missing",
        )
    })?;
    directory(Path::new(&runtime), &signature)
}

pub async fn request(directory: &Path, command: &str) -> io::Result<String> {
    if command.is_empty() || command.len() > 64 * 1024 || command.contains(['\0', '\n', '\r']) {
        return Err(io::Error::new(
            ErrorKind::InvalidInput,
            "Invalid Hyprland request",
        ));
    }
    tokio::time::timeout(Duration::from_secs(2), async {
        // Hyprland handles socket1 synchronously; never retain an idle connection.
        let mut socket = UnixStream::connect(directory.join(".socket.sock")).await?;
        socket.write_all(command.as_bytes()).await?;
        let mut reply = Vec::new();
        socket.take(MAX_REPLY + 1).read_to_end(&mut reply).await?;
        if reply.len() as u64 > MAX_REPLY {
            return Err(io::Error::new(
                ErrorKind::InvalidData,
                "Hyprland reply is too large",
            ));
        }
        String::from_utf8(reply).map_err(|error| io::Error::new(ErrorKind::InvalidData, error))
    })
    .await
    .map_err(|_| io::Error::new(ErrorKind::TimedOut, "Hyprland request timed out"))?
}

async fn next_event(reader: &mut BufReader<UnixStream>) -> io::Result<HyprlandUpdate> {
    let mut line = String::new();
    let size = reader.take(MAX_EVENT + 1).read_line(&mut line).await?;
    if size == 0 {
        return Err(io::Error::new(
            ErrorKind::UnexpectedEof,
            "Hyprland event socket closed",
        ));
    }
    if size as u64 > MAX_EVENT || !line.ends_with('\n') {
        return Err(io::Error::new(
            ErrorKind::InvalidData,
            "Invalid Hyprland event frame",
        ));
    }
    let (name, data) = line
        .trim_end_matches('\n')
        .split_once(">>")
        .filter(|(name, _)| !name.is_empty())
        .ok_or_else(|| io::Error::new(ErrorKind::InvalidData, "Invalid Hyprland event"))?;
    Ok(HyprlandUpdate {
        kind: "event".into(),
        name: name.into(),
        data: data.into(),
    })
}

async fn connected(
    sender: &broadcast::Sender<HyprlandUpdate>,
    status: &watch::Sender<Option<HyprlandUpdate>>,
) -> io::Result<()> {
    let directory = socket_directory()?;
    let socket = UnixStream::connect(directory.join(".socket2.sock")).await?;
    let mut reader = BufReader::new(socket);
    let version = request(&directory, "j/version").await?;
    let update = HyprlandUpdate {
        kind: "connected".into(),
        name: "version".into(),
        data: version,
    };
    status.send_replace(Some(update.clone()));
    let _ = sender.send(update);
    loop {
        let _ = sender.send(next_event(&mut reader).await?);
    }
}

pub async fn listen(
    sender: broadcast::Sender<HyprlandUpdate>,
    status: watch::Sender<Option<HyprlandUpdate>>,
) {
    loop {
        if let Err(error) = connected(&sender, &status).await {
            let update = HyprlandUpdate {
                kind: "disconnected".into(),
                name: String::new(),
                data: error.to_string(),
            };
            status.send_replace(Some(update.clone()));
            let _ = sender.send(update);
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::net::UnixListener;

    fn run(test: impl Future<Output = ()>) {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(test);
    }

    #[test]
    fn validates_xdg_session_paths() {
        assert_eq!(
            directory(Path::new("/run/user/1000"), "instance").unwrap(),
            PathBuf::from("/run/user/1000/hypr/instance")
        );
        for signature in ["", "..", "/tmp", "a/b"] {
            assert!(directory(Path::new("/run/user/1000"), signature).is_err());
        }
        assert!(directory(Path::new("relative"), "instance").is_err());
    }

    #[test]
    fn requests_use_separate_connections_and_preserve_full_replies() {
        run(async {
            let root = tempfile::tempdir().unwrap();
            let listener = UnixListener::bind(root.path().join(".socket.sock")).unwrap();
            let server = tokio::spawn(async move {
                for _ in 0..2 {
                    let (mut socket, _) = listener.accept().await.unwrap();
                    let mut command = [0; 10];
                    socket.read_exact(&mut command).await.unwrap();
                    assert_eq!(&command, b"j/monitors");
                    socket.write_all(b"[{\"name\":").await.unwrap();
                    socket.write_all(b"\"DP-1\"}]").await.unwrap();
                }
            });
            for _ in 0..2 {
                assert_eq!(
                    request(root.path(), "j/monitors").await.unwrap(),
                    "[{\"name\":\"DP-1\"}]"
                );
            }
            server.await.unwrap();
            assert!(request(root.path(), "bad\nrequest").await.is_err());
        });
    }

    #[test]
    fn frames_preserve_partial_writes_unknown_events_and_commas() {
        run(async {
            let (mut server, client) = UnixStream::pair().unwrap();
            let writer = tokio::spawn(async move {
                server.write_all(b"future").await.unwrap();
                tokio::task::yield_now().await;
                server
                    .write_all(b">>a,b>>c\nconfigreloaded>>\n")
                    .await
                    .unwrap();
            });
            let mut reader = BufReader::new(client);
            let event = next_event(&mut reader).await.unwrap();
            assert_eq!(event.name, "future");
            assert_eq!(event.data, "a,b>>c");
            assert_eq!(next_event(&mut reader).await.unwrap().data, "");
            assert!(next_event(&mut reader).await.is_err());
            writer.await.unwrap();
        });
    }

    #[test]
    fn rejects_malformed_and_oversized_frames() {
        run(async {
            for frame in [
                "invalid\n".to_owned(),
                ">>missing\n".to_owned(),
                "event>>partial".to_owned(),
                format!("event>>{}\n", "a".repeat(MAX_EVENT as usize)),
            ] {
                let (mut server, client) = UnixStream::pair().unwrap();
                tokio::spawn(async move {
                    let _ = server.write_all(frame.as_bytes()).await;
                });
                assert!(next_event(&mut BufReader::new(client)).await.is_err());
            }
        });
    }

    #[test]
    fn request_timeout_closes_the_connection() {
        run(async {
            let root = tempfile::tempdir().unwrap();
            let listener = UnixListener::bind(root.path().join(".socket.sock")).unwrap();
            let server = tokio::spawn(async move {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut command = [0; 9];
                socket.read_exact(&mut command).await.unwrap();
                assert_eq!(&command, b"j/version");
                let mut rest = Vec::new();
                socket.read_to_end(&mut rest).await.unwrap();
                assert!(rest.is_empty());
            });
            assert_eq!(
                request(root.path(), "j/version").await.unwrap_err().kind(),
                ErrorKind::TimedOut
            );
            server.await.unwrap();
        });
    }
}
