use crate::api::{
    HyprlandMonitor, HyprlandSnapshot, HyprlandWindow, HyprlandWorkspace, HyprlandWorkspaceSlot,
};
use serde::Deserialize;
use std::collections::HashSet;

#[derive(Deserialize)]
struct WorkspaceRef {
    id: Option<i32>,
    name: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Monitor {
    id: i32,
    name: String,
    x: i32,
    y: i32,
    active_workspace: WorkspaceRef,
    special_workspace: WorkspaceRef,
}

#[derive(Deserialize)]
struct Workspace {
    id: i32,
    name: String,
    monitor: String,
    windows: u32,
    lastwindow: String,
    #[serde(rename = "type")]
    workspace_type: Option<String>,
}

#[derive(Deserialize)]
struct Client {
    address: String,
    title: String,
    class: String,
    workspace: WorkspaceRef,
    monitor: i32,
    mapped: bool,
    hidden: bool,
    #[serde(rename = "focusHistoryID")]
    focus_history: i32,
    #[serde(default)]
    size: [i32; 2],
}

#[derive(Deserialize)]
struct ActiveWindow {
    address: Option<String>,
}

pub fn parse(
    monitors: &str,
    workspaces: &str,
    clients: &str,
    active_window: &str,
    urgent: &HashSet<i32>,
) -> Result<HyprlandSnapshot, String> {
    let mut monitors: Vec<Monitor> =
        serde_json::from_str(monitors).map_err(|error| error.to_string())?;
    let workspaces: Vec<Workspace> =
        serde_json::from_str(workspaces).map_err(|error| error.to_string())?;
    let clients: Vec<Client> = serde_json::from_str(clients).map_err(|error| error.to_string())?;
    let active: ActiveWindow =
        serde_json::from_str(active_window).map_err(|error| error.to_string())?;
    if monitors.iter().any(|monitor| {
        monitor.name.is_empty()
            || monitor.active_workspace.id.is_none()
            || monitors
                .iter()
                .filter(|other| other.name == monitor.name)
                .count()
                != 1
    }) {
        return Err("Invalid Hyprland monitor snapshot".into());
    }
    monitors.sort_by(|a, b| (a.y, a.x, &a.name).cmp(&(b.y, b.x, &b.name)));
    let window = |client: &Client| HyprlandWindow {
        address: client.address.clone(),
        title: client.title.clone(),
        app_id: client.class.clone(),
        workspace_id: client.workspace.id.unwrap_or_default(),
        monitor_name: monitors
            .iter()
            .find(|monitor| monitor.id == client.monitor)
            .map(|monitor| monitor.name.clone())
            .unwrap_or_default(),
    };
    Ok(HyprlandSnapshot {
        monitors: monitors
            .iter()
            .enumerate()
            .map(|(index, monitor)| {
                let active_id = monitor.active_workspace.id.unwrap();
                let special_id = monitor.special_workspace.id.filter(|id| *id != 0);
                let visible = |client: &&Client| {
                    client.monitor == monitor.id
                        && client.mapped
                        && !client.hidden
                        && (client.workspace.id == Some(active_id)
                            || special_id.is_some() && client.workspace.id == special_id)
                };
                let selected_id = special_id.unwrap_or(active_id);
                let last_window = workspaces
                    .iter()
                    .find(|workspace| workspace.id == selected_id)
                    .map(|workspace| workspace.lastwindow.as_str());
                let current_window = clients.iter().filter(visible).min_by_key(|client| {
                    (
                        active.address.as_deref() != Some(client.address.as_str()),
                        last_window != Some(client.address.as_str()),
                        client.workspace.id != Some(selected_id),
                        client.focus_history < 0,
                        client.focus_history,
                    )
                });
                HyprlandMonitor {
                    name: monitor.name.clone(),
                    output_number: index as u32 + 1,
                    x: monitor.x,
                    y: monitor.y,
                    active_workspace_id: active_id,
                    special_workspace_id: special_id,
                    special_workspace_name: monitor
                        .special_workspace
                        .name
                        .clone()
                        .filter(|name| !name.is_empty()),
                    current_window: current_window.map(window),
                    workspace_slots: slots(active_id, &workspaces, &clients, urgent),
                }
            })
            .collect(),
        workspaces: {
            let mut result: Vec<_> = workspaces
                .iter()
                .filter(|workspace| {
                    workspace.id != 0
                        && workspace.workspace_type.as_deref() != Some("special")
                        && !workspace.name.starts_with("special:")
                })
                .map(|workspace| HyprlandWorkspace {
                    id: workspace.id,
                    name: workspace.name.clone(),
                    monitor_name: workspace.monitor.clone(),
                    window_count: workspace.windows,
                    windows: clients
                        .iter()
                        .filter(|client| client.workspace.id == Some(workspace.id) && client.mapped)
                        .map(window)
                        .collect(),
                })
                .collect();
            result.sort_by_key(|workspace| workspace.id);
            result
        },
    })
}

fn slots(
    active_id: i32,
    workspaces: &[Workspace],
    clients: &[Client],
    urgent: &HashSet<i32>,
) -> Vec<HyprlandWorkspaceSlot> {
    // Match this workstation's ii layout: eight slots, each in the active numeric group.
    let start = if active_id > 0 {
        (active_id - 1) / 8 * 8 + 1
    } else {
        1
    };
    (0..8)
        .map(|offset| {
            let id = start.checked_add(offset).unwrap_or_default();
            let workspace = workspaces.iter().find(|workspace| workspace.id == id);
            let mut windows: Vec<_> = clients
                .iter()
                .filter(|client| client.mapped && client.workspace.id == Some(id))
                .collect();
            windows.sort_by_key(|client| {
                std::cmp::Reverse(
                    i64::from(client.size[0].max(0)) * i64::from(client.size[1].max(0)),
                )
            });
            let mut seen = HashSet::new();
            let apps = windows
                .into_iter()
                .filter(|client| seen.insert(client.class.as_str()))
                .map(|client| client.class.clone())
                .collect();
            HyprlandWorkspaceSlot {
                id,
                name: workspace
                    .map(|workspace| workspace.name.clone())
                    .unwrap_or_else(|| {
                        if id == 0 {
                            "—".into()
                        } else {
                            id.to_string()
                        }
                    }),
                active: id == active_id,
                occupied: workspace.is_some_and(|workspace| workspace.windows > 0),
                window_count: workspace
                    .map(|workspace| workspace.windows)
                    .unwrap_or_default(),
                owner: workspace
                    .map(|workspace| workspace.monitor.clone())
                    .filter(|name| !name.is_empty()),
                apps,
                urgent: urgent.contains(&id),
            }
        })
        .collect()
}

fn quoted(value: &str) -> Result<String, String> {
    if value.is_empty() || value.chars().any(char::is_control) {
        return Err("Invalid workspace target".into());
    }
    serde_json::to_string(value).map_err(|error| error.to_string())
}

fn output(snapshot: &HyprlandSnapshot, name: &str) -> Result<String, String> {
    if !snapshot.monitors.iter().any(|monitor| monitor.name == name) {
        return Err("Output unavailable".into());
    }
    Ok(format!(
        "local focus = hl.dispatch(hl.dsp.focus({{monitor = {}}})); if not focus.ok then return focus.error or 'Output unavailable' end; ",
        quoted(name)?
    ))
}

pub fn switch_command(
    snapshot: &HyprlandSnapshot,
    output_name: &str,
    id: i32,
) -> Result<String, String> {
    let owner = output(snapshot, output_name)?;
    let workspace = snapshot
        .workspaces
        .iter()
        .find(|workspace| workspace.id == id);
    let (prefix, selector) = match workspace {
        // Existing workspaces stay on their monitor; focusing them never moves them.
        Some(workspace) => (
            output(snapshot, &workspace.monitor_name).unwrap_or_default(),
            if id > 0 {
                id.to_string()
            } else {
                format!("name:{}", workspace.name)
            },
        ),
        None if id > 0
            && snapshot
                .monitors
                .iter()
                .find(|monitor| monitor.name == output_name)
                .is_some_and(|monitor| {
                    monitor.workspace_slots.iter().any(|slot| slot.id == id)
                }) =>
        {
            (owner, id.to_string())
        }
        None => return Err("Workspace target is outside the current group".into()),
    };
    Ok(dispatch(
        &prefix,
        &format!("hl.dsp.focus({{workspace = {}}})", quoted(&selector)?),
    ))
}

pub fn scroll_command(
    snapshot: &HyprlandSnapshot,
    output_name: &str,
    direction: i32,
) -> Result<String, String> {
    if !matches!(direction, -1 | 1) {
        return Err("Invalid workspace scroll direction".into());
    }
    let owner = output(snapshot, output_name)?;
    let selector = if direction == 1 { "r+1" } else { "r-1" };
    Ok(dispatch(
        &owner,
        &format!("hl.dsp.focus({{workspace = \"{selector}\"}})"),
    ))
}

pub fn special_command(snapshot: &HyprlandSnapshot, output_name: &str) -> Result<String, String> {
    let owner = output(snapshot, output_name)?;
    let monitor = snapshot
        .monitors
        .iter()
        .find(|monitor| monitor.name == output_name)
        .ok_or("Output unavailable")?;
    let special = monitor
        .special_workspace_name
        .as_deref()
        .and_then(|name| name.strip_prefix("special:"))
        .filter(|name| !name.is_empty())
        .unwrap_or("special");
    Ok(dispatch(
        &owner,
        &format!("hl.dsp.workspace.toggle_special({})", quoted(special)?),
    ))
}

fn dispatch(prefix: &str, action: &str) -> String {
    format!(
        "repl {prefix}local result = hl.dispatch({action}); return result.ok and 'ok' or (result.error or 'Workspace action failed')"
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn snapshot(hidden: bool, active_workspace: i32) -> HyprlandSnapshot {
        let monitors = json!([
            {"id": 0, "name": "DP-1", "x": 0, "y": 0,
             "activeWorkspace": {"id": 1}, "specialWorkspace": {}},
            {"id": 1, "name": "DP-2", "x": 1920, "y": 0,
             "activeWorkspace": {"id": 2}, "specialWorkspace": {"id": 0}}
        ]);
        let workspaces = json!([
            {"id": 3, "name": "3", "monitor": "DP-1", "windows": 0, "lastwindow": ""},
            {"id": 2, "name": "Code", "monitor": "DP-2", "windows": 1, "lastwindow": "0xb"},
            {"id": 1, "name": "1", "monitor": "DP-1", "windows": 1, "lastwindow": "0xa"}
        ]);
        let clients = json!([
            {"address": "0xa", "title": "First", "class": "editor", "workspace": {"id": 1},
             "monitor": 0, "mapped": true, "hidden": false, "focusHistoryID": 1},
            {"address": "0xb", "title": "Second", "class": "browser", "workspace": {"id": active_workspace},
             "monitor": 1, "mapped": true,
             "hidden": hidden, "focusHistoryID": 0}
        ]);
        parse(
            &monitors.to_string(),
            &workspaces.to_string(),
            &clients.to_string(),
            r#"{"address":"0xa"}"#,
            &HashSet::from([10]),
        )
        .unwrap()
    }

    #[test]
    fn output_numbers_follow_rows_then_horizontal_position() {
        let state = parse(
            r#"[
                {"id":0,"name":"lower-left","x":-1920,"y":1080,"activeWorkspace":{"id":1},"specialWorkspace":{}},
                {"id":3,"name":"top-right","x":1920,"y":0,"activeWorkspace":{"id":2},"specialWorkspace":{}},
                {"id":1,"name":"top-left","x":0,"y":0,"activeWorkspace":{"id":3},"specialWorkspace":{}}
            ]"#,
            "[]",
            "[]",
            "{}",
            &HashSet::new(),
        ).unwrap();
        assert_eq!(
            state
                .monitors
                .iter()
                .map(|m| (m.name.as_str(), m.output_number))
                .collect::<Vec<_>>(),
            [("top-left", 1), ("top-right", 2), ("lower-left", 3)]
        );
    }

    #[test]
    fn current_window_is_resolved_per_output_even_when_unfocused() {
        let state = snapshot(false, 2);
        assert_eq!(
            state.monitors[0].current_window.as_ref().unwrap().title,
            "First"
        );
        assert_eq!(
            state.monitors[1].current_window.as_ref().unwrap().title,
            "Second"
        );
        assert_eq!(
            state
                .workspaces
                .iter()
                .map(|workspace| workspace.id)
                .collect::<Vec<_>>(),
            [1, 2, 3]
        );
        assert_eq!(state.workspaces[1].windows[0].monitor_name, "DP-2");
    }

    #[test]
    fn hidden_and_off_workspace_windows_are_not_current() {
        assert!(snapshot(true, 2).monitors[1].current_window.is_none());
        assert!(snapshot(false, 3).monitors[1].current_window.is_none());
    }

    #[test]
    fn named_workspaces_and_visible_special_windows_are_supported() {
        let state = parse(
            r#"[{"id":0,"name":"DP-1","x":0,"y":0,"activeWorkspace":{"id":-1337},"specialWorkspace":{"id":-99}}]"#,
            r#"[{"id":-1337,"type":"normal","name":"Writing","monitor":"DP-1","windows":0,"lastwindow":""},{"id":-99,"type":"special","name":"special:scratch","monitor":"DP-1","windows":1,"lastwindow":"0xa"}]"#,
            r#"[{"address":"0xa","title":"Scratch","class":"terminal","workspace":{"id":-99},"monitor":0,"mapped":true,"hidden":false,"focusHistoryID":0}]"#,
            "{}",
            &HashSet::new(),
        ).unwrap();
        assert_eq!(state.workspaces.len(), 1);
        assert_eq!(state.workspaces[0].id, -1337);
        assert_eq!(
            state.monitors[0].current_window.as_ref().unwrap().title,
            "Scratch"
        );
    }

    #[test]
    fn invalid_data_and_command_targets_are_rejected() {
        assert!(parse("{}", "[]", "[]", "{}", &HashSet::new()).is_err());
        assert!(parse("[]", "[]", "[]", "invalid", &HashSet::new()).is_err());
        let state = snapshot(false, 2);
        assert!(switch_command(&state, "DP-1\n", 1).is_err());
        assert!(switch_command(&state, "DP-1", 0).is_err());
        assert!(switch_command(&state, "DP-1", 42).is_err());
        let command = switch_command(&state, "DP-1", 4).unwrap();
        assert!(command.contains("monitor = \"DP-1\""));
        assert!(command.contains("workspace = \"4\""));
        assert!(quoted("DP-\"1").unwrap().contains(r#"DP-\"1"#));
        assert!(quoted("bad\nname").is_err());
        assert!(scroll_command(&state, "DP-1", 0).is_err());
        assert!(scroll_command(&state, "missing", 1).is_err());
    }

    #[test]
    fn fixed_group_slots_use_global_occupancy_and_largest_window_icons() {
        let state = parse(
            r#"[{"id":0,"name":"DP-1","x":0,"y":0,"activeWorkspace":{"id":14},"specialWorkspace":{}},{"id":1,"name":"DP-2","x":1920,"y":0,"activeWorkspace":{"id":10},"specialWorkspace":{}}]"#,
            r#"[{"id":14,"name":"14","monitor":"DP-1","windows":2,"lastwindow":"0xa"},{"id":10,"name":"10","monitor":"DP-2","windows":1,"lastwindow":"0xb"},{"id":-1337,"name":"Writing","monitor":"DP-2","windows":0,"lastwindow":""}]"#,
            r#"[{"address":"0xa","title":"Small","class":"small","workspace":{"id":14},"monitor":0,"mapped":true,"hidden":false,"focusHistoryID":0,"size":[100,100]},{"address":"0xc","title":"Large","class":"large","workspace":{"id":14},"monitor":0,"mapped":true,"hidden":false,"focusHistoryID":1,"size":[1000,500]},{"address":"0xb","title":"Other output","class":"other","workspace":{"id":10},"monitor":1,"mapped":true,"hidden":false,"focusHistoryID":2,"size":[300,300]}]"#,
            r#"{"address":"0xa"}"#,
            &HashSet::from([10]),
        ).unwrap();
        let slots = &state.monitors[0].workspace_slots;
        assert_eq!(
            slots.iter().map(|slot| slot.id).collect::<Vec<_>>(),
            (9..=16).collect::<Vec<_>>()
        );
        assert!(slots[5].active);
        assert_eq!(slots[5].apps, ["large", "small"]);
        assert_eq!(slots[1].apps, ["other"]);
        assert_eq!(slots[1].owner.as_deref(), Some("DP-2"));
        assert!(slots[1].urgent);
        assert!(slots[1].occupied);
        assert!(!slots[0].occupied);
        let command = switch_command(&state, "DP-1", 10).unwrap();
        assert!(command.contains("monitor = \"DP-2\""));
        assert!(command.contains("workspace = \"10\""));
        assert!(
            switch_command(&state, "DP-1", 15)
                .unwrap()
                .contains("monitor = \"DP-1\"")
        );
        assert!(switch_command(&state, "DP-1", 17).is_err());
        assert!(
            switch_command(&state, "DP-1", -1337)
                .unwrap()
                .contains("workspace = \"name:Writing\"")
        );
        assert!(
            scroll_command(&state, "DP-1", 1)
                .unwrap()
                .contains("workspace = \"r+1\"}))")
        );
        assert!(
            special_command(&state, "DP-1")
                .unwrap()
                .contains("toggle_special(\"special\")")
        );
    }
}
