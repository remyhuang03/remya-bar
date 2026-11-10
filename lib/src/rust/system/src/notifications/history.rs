use super::{Entry, HISTORY_LIMIT, IMAGE_LIMIT, NotificationSnapshot};
use rusqlite::{Connection, OptionalExtension, params};
use std::fs::{DirBuilder, File, OpenOptions};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::time::Duration;

pub(super) fn open() -> Result<(History, Vec<Entry>, u32), String> {
    let absolute = |name| {
        std::env::var_os(name)
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
    };
    let root = absolute("XDG_STATE_HOME")
        .or_else(|| absolute("HOME").map(|home| home.join(".local/state")))
        .ok_or("An absolute XDG_STATE_HOME or HOME is required")?;
    History::open(&root.join("remya/bar"))
}

pub(super) struct History {
    db: Connection,
    // Session buses are separate but can share the same XDG state directory.
    _lock: File,
    dirty: bool,
}

impl History {
    pub(super) fn open(directory: &Path) -> Result<(Self, Vec<Entry>, u32), String> {
        DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(directory)
            .map_err(|error| error.to_string())?;
        let private_file = |path| {
            OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(false)
                .mode(0o600)
                .open(path)
                .map_err(|error| error.to_string())
        };
        let lock = private_file(directory.join("notifications.lock"))?;
        lock.try_lock().map_err(|error| error.to_string())?;
        let path = directory.join("notifications.sqlite3");
        private_file(path.clone())?;
        let db = Connection::open(path).map_err(|error| error.to_string())?;
        db.busy_timeout(Duration::from_millis(250))
            .and_then(|()| {
                db.execute_batch(
                    "PRAGMA synchronous = FULL;
                     PRAGMA secure_delete = ON;
                     CREATE TABLE IF NOT EXISTS history (
                         id INTEGER PRIMARY KEY, sort_order INTEGER NOT NULL,
                         snapshot TEXT NOT NULL, image BLOB NOT NULL
                     );
                     CREATE TABLE IF NOT EXISTS state (
                         id INTEGER PRIMARY KEY CHECK (id = 1), next_id INTEGER NOT NULL
                     );",
                )
            })
            .map_err(|error| error.to_string())?;
        let next_id = db
            .query_row("SELECT next_id FROM state WHERE id = 1", [], |row| {
                row.get(0)
            })
            .optional()
            .map_err(|error| error.to_string())?
            .filter(|id| *id != 0)
            .unwrap_or(1);
        let entries = Self::load(&db).map_err(|error| error.to_string())?;
        Ok((
            Self {
                db,
                _lock: lock,
                dirty: false,
            },
            entries,
            next_id,
        ))
    }

    fn load(db: &Connection) -> rusqlite::Result<Vec<Entry>> {
        let mut statement = db.prepare(
            "SELECT id, sort_order, snapshot, image FROM history
             ORDER BY sort_order DESC LIMIT ?1",
        )?;
        let mut rows = statement.query([HISTORY_LIMIT as i64])?;
        let mut entries = Vec::new();
        while let Some(row) = rows.next()? {
            let id: u32 = row.get(0)?;
            let payload: String = row.get(2)?;
            let mut snapshot = match serde_json::from_str::<NotificationSnapshot>(&payload) {
                Ok(snapshot) if snapshot.id == id && id != 0 => snapshot,
                _ => {
                    eprintln!("Notification history: skipped invalid record {id}");
                    continue;
                }
            };
            let image: Vec<u8> = row.get(3)?;
            let (width, height) = (snapshot.image_width, snapshot.image_height);
            if (1..=IMAGE_LIMIT).contains(&width)
                && (1..=IMAGE_LIMIT).contains(&height)
                && image.len() == (width * height * 4) as usize
            {
                snapshot.image_argb = image;
            } else {
                snapshot.image_width = 0;
                snapshot.image_height = 0;
            }
            entries.push(Entry {
                snapshot,
                order: row.get(1)?,
                timeout: None,
                deadline: None,
                remaining: None,
            });
        }
        Ok(entries)
    }

    pub(super) fn needs_retry(&self) -> bool {
        self.dirty
    }

    pub(super) fn save(
        &mut self,
        entries: &[Entry],
        next_id: u32,
        changed: Option<u32>,
        removed: &[u32],
    ) -> Result<(), String> {
        let result = self
            .write(entries, next_id, changed, removed)
            .map_err(|error| error.to_string());
        self.dirty = result.is_err();
        result
    }

    fn write(
        &mut self,
        entries: &[Entry],
        next_id: u32,
        changed: Option<u32>,
        removed: &[u32],
    ) -> Result<(), Box<dyn std::error::Error>> {
        let transaction = self.db.transaction()?;
        if self.dirty {
            transaction.execute("DELETE FROM history", [])?;
        } else {
            let mut delete = transaction.prepare_cached("DELETE FROM history WHERE id = ?1")?;
            for id in changed.iter().chain(removed) {
                delete.execute([id])?;
            }
        }
        {
            let mut insert =
                transaction.prepare_cached("INSERT INTO history VALUES (?1, ?2, ?3, ?4)")?;
            for entry in entries {
                let item = &entry.snapshot;
                if !item.transient && (self.dirty || changed == Some(item.id)) {
                    insert.execute(params![
                        item.id,
                        entry.order,
                        serde_json::to_string(item)?,
                        item.image_argb
                    ])?;
                }
            }
        }
        transaction.execute(
            "INSERT INTO state VALUES (1, ?1)
             ON CONFLICT(id) DO UPDATE SET next_id = excluded.next_id",
            [next_id],
        )?;
        transaction.commit()?;
        Ok(())
    }
}
