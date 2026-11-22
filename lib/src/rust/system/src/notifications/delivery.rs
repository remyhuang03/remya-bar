//! Quiet hours and delivery policies for notification alerts.

use super::{NotificationPreferences, NotificationSnapshot};
use chrono::{Datelike, NaiveDateTime, Timelike};
use std::time::Duration;

/// Critical, call and priority app notifications break through Do Not Disturb.
pub(super) fn bypasses(
    preferences: &NotificationPreferences,
    snapshot: &NotificationSnapshot,
) -> bool {
    snapshot.urgency == 2
        || preferences.priority_calls
            && (snapshot.category == "call" || snapshot.category.starts_with("call."))
        || preferences.priority_apps.iter().any(|app| {
            (!snapshot.desktop_entry.is_empty()
                && app.id.eq_ignore_ascii_case(&snapshot.desktop_entry))
                || (!snapshot.app_name.is_empty()
                    && app.name.eq_ignore_ascii_case(&snapshot.app_name))
        })
}

/// Whether the schedule covers `now`; a period crossing midnight belongs to
/// the day it starts. Equal start and end times mean no period.
pub(super) fn scheduled(preferences: &NotificationPreferences, now: NaiveDateTime) -> bool {
    let (start, end) = (
        preferences.schedule_start_minutes,
        preferences.schedule_end_minutes,
    );
    let minute = now.hour() * 60 + now.minute();
    let today = now.weekday().number_from_monday();
    let yesterday = now.weekday().pred().number_from_monday();
    let starts = |day: u32| preferences.schedule_days.contains(&day);
    if start < end {
        starts(today) && (start..end).contains(&minute)
    } else if start > end {
        starts(today) && minute >= start || starts(yesterday) && minute < end
    } else {
        false
    }
}

/// Duration until the next quiet-hours start or end boundary after `now`.
pub(super) fn next_schedule_boundary(
    preferences: &NotificationPreferences,
    now: NaiveDateTime,
) -> Option<Duration> {
    let (start, end) = (
        preferences.schedule_start_minutes,
        preferences.schedule_end_minutes,
    );
    if !preferences.schedule || start == end || preferences.schedule_days.is_empty() {
        return None;
    }
    let start_time = chrono::NaiveTime::from_num_seconds_from_midnight_opt(start * 60, 0)?;
    let end_time = chrono::NaiveTime::from_num_seconds_from_midnight_opt(end * 60, 0)?;
    let today = now.date();
    let mut earliest: Option<NaiveDateTime> = None;
    for offset in -1..=7 {
        let Some(date) = today.checked_add_signed(chrono::TimeDelta::days(offset)) else {
            continue;
        };
        if !preferences
            .schedule_days
            .contains(&date.weekday().number_from_monday())
        {
            continue;
        }
        let start_dt = date.and_time(start_time);
        let end_date = if start < end { date } else { date.succ_opt()? };
        let end_dt = end_date.and_time(end_time);
        for candidate in [start_dt, end_dt] {
            if candidate > now && earliest.is_none_or(|best| candidate < best) {
                earliest = Some(candidate);
            }
        }
    }
    earliest.and_then(|dt| (dt - now).to_std().ok())
}

/// Plays the requested sound or the theme's message sound through libcanberra.
pub(super) fn play_sound(file: Option<String>, name: Option<String>) {
    let mut command = tokio::process::Command::new("canberra-gtk-play");
    match (file, name) {
        (Some(file), _) => command.args(["-f", &file]),
        (None, Some(name)) => command.args(["-i", &name]),
        (None, None) => command.args(["-i", "message-new-instant"]),
    };
    command.arg("-d").arg("Notification");
    match command.kill_on_drop(false).spawn() {
        Ok(mut child) => {
            tokio::spawn(async move {
                let _ = child.wait().await;
            });
        }
        Err(error) => eprintln!("Notification sound: {error}"),
    }
}
