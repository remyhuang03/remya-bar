//! Validates notification hints and converts markup and images for the UI.

use super::IMAGE_LIMIT;
use crate::api::{NotificationAction, NotificationText};
use std::collections::HashMap;
use zbus::zvariant::{OwnedValue, Value};

pub(super) fn hint_string(hints: &HashMap<String, OwnedValue>, key: &str) -> Option<String> {
    hints
        .get(key)
        .and_then(|value| <&str>::try_from(value).ok())
        .map(str::to_owned)
        .filter(|value| !value.is_empty() && value.len() <= 4096)
}

pub(super) fn hint_bool(hints: &HashMap<String, OwnedValue>, key: &str) -> bool {
    hints.get(key).is_some_and(|value| match &**value {
        Value::Bool(value) => *value,
        Value::U8(value) => *value != 0,
        Value::I32(value) => *value != 0,
        _ => false,
    })
}

pub(super) fn hint_byte(hints: &HashMap<String, OwnedValue>, key: &str) -> Option<u8> {
    hint_int(hints, key).and_then(|value| u8::try_from(value).ok())
}

pub(super) fn hint_int(hints: &HashMap<String, OwnedValue>, key: &str) -> Option<i32> {
    match &**hints.get(key)? {
        Value::U8(value) => Some(i32::from(*value)),
        Value::I16(value) => Some(i32::from(*value)),
        Value::U16(value) => Some(i32::from(*value)),
        Value::I32(value) => Some(*value),
        Value::U32(value) => i32::try_from(*value).ok(),
        Value::I64(value) => i32::try_from(*value).ok(),
        Value::U64(value) => i32::try_from(*value).ok(),
        _ => None,
    }
}

pub(super) fn parse_actions(flat: Vec<String>) -> (Vec<NotificationAction>, bool) {
    let mut default_action = false;
    let mut actions = Vec::new();
    for pair in flat.as_chunks::<2>().0 {
        if pair[0] == "default" {
            default_action = true;
        } else if !pair[0].is_empty() {
            actions.push(NotificationAction {
                key: pair[0].clone(),
                label: pair[1].clone(),
            });
        }
    }
    (actions, default_action)
}

/// Decodes `(iiibiiay)` image hints into tray-compatible ARGB, at most 128 px.
pub(super) fn image_data(value: &OwnedValue) -> Option<(Vec<u8>, u32, u32)> {
    let Value::Structure(structure) = &**value else {
        return None;
    };
    let fields = structure.fields();
    if fields.len() != 7 {
        return None;
    }
    let int = |index: usize| match &fields[index] {
        Value::I32(value) => Some(*value),
        _ => None,
    };
    let (width, height, rowstride) = (int(0)?, int(1)?, int(2)?);
    let Value::Bool(has_alpha) = fields[3] else {
        return None;
    };
    let (bits, channels) = (int(4)?, int(5)?);
    let Value::Array(array) = &fields[6] else {
        return None;
    };
    let data: Vec<u8> = array
        .iter()
        .filter_map(|byte| u8::try_from(byte).ok())
        .collect();
    decode_pixels(width, height, rowstride, has_alpha, bits, channels, &data)
}

fn decode_pixels(
    width: i32,
    height: i32,
    rowstride: i32,
    has_alpha: bool,
    bits: i32,
    channels: i32,
    data: &[u8],
) -> Option<(Vec<u8>, u32, u32)> {
    if !(1..=4096).contains(&width)
        || !(1..=4096).contains(&height)
        || bits != 8
        || channels != if has_alpha { 4 } else { 3 }
        || rowstride < width * channels
    {
        return None;
    }
    let (width, height, rowstride, channels) = (
        width as usize,
        height as usize,
        rowstride as usize,
        channels as usize,
    );
    if data.len() < rowstride * (height - 1) + width * channels {
        return None;
    }
    let scale = (width.max(height) as f64 / f64::from(IMAGE_LIMIT)).max(1.0);
    let target_width = ((width as f64 / scale).round() as usize).max(1);
    let target_height = ((height as f64 / scale).round() as usize).max(1);
    let mut argb = Vec::with_capacity(target_width * target_height * 4);
    for y in 0..target_height {
        let source_y = ((y as f64 + 0.5) * scale) as usize;
        for x in 0..target_width {
            let source_x = ((x as f64 + 0.5) * scale) as usize;
            let offset = source_y.min(height - 1) * rowstride + source_x.min(width - 1) * channels;
            let pixel = &data[offset..offset + channels];
            argb.extend_from_slice(&[
                if has_alpha { pixel[3] } else { 255 },
                pixel[0],
                pixel[1],
                pixel[2],
            ]);
        }
    }
    Some((argb, target_width as u32, target_height as u32))
}

/// Keeps `<b> <i> <u> <a href>` runs; malformed markup falls back to the raw text.
pub(super) fn parse_body(body: &str) -> Vec<NotificationText> {
    parse_markup(body).unwrap_or_else(|| {
        if body.is_empty() {
            Vec::new()
        } else {
            vec![run(body.to_owned(), [false; 3], String::new())]
        }
    })
}

fn run(text: String, style: [bool; 3], href: String) -> NotificationText {
    NotificationText {
        text,
        bold: style[0],
        italic: style[1],
        underline: style[2],
        href,
    }
}

fn parse_markup(body: &str) -> Option<Vec<NotificationText>> {
    let mut runs: Vec<NotificationText> = Vec::new();
    let mut open: Vec<String> = Vec::new();
    let mut style = [false; 3];
    let mut href = String::new();
    let mut text = String::new();
    let mut rest = body;
    let mut flush = |text: &mut String, style: [bool; 3], href: &str| {
        if text.is_empty() {
            return;
        }
        match runs.last_mut() {
            Some(last)
                if [last.bold, last.italic, last.underline] == style && last.href == href =>
            {
                last.text.push_str(text)
            }
            _ => runs.push(run(text.clone(), style, href.to_owned())),
        }
        text.clear();
    };
    while let Some(start) = rest.find(['<', '&']) {
        text.push_str(&rest[..start]);
        rest = &rest[start..];
        if rest.starts_with('&') {
            let end = rest.find(';').filter(|end| *end <= 10)?;
            text.push(entity(&rest[1..end])?);
            rest = &rest[end + 1..];
            continue;
        }
        let end = rest.find('>')?;
        let tag = rest[1..end].trim();
        rest = &rest[end + 1..];
        let closing = tag.strip_prefix('/');
        let name = closing
            .unwrap_or(tag)
            .split(|c: char| c.is_whitespace() || c == '/')
            .next()?
            .to_ascii_lowercase();
        if name.is_empty() || !name.chars().all(|c| c.is_ascii_alphanumeric()) {
            return None;
        }
        if matches!(name.as_str(), "br" | "img") {
            if name == "br" {
                text.push('\n');
            }
            continue;
        }
        flush(&mut text, style, &href);
        if closing.is_some() {
            if open.pop()? != name {
                return None;
            }
        } else if !tag.ends_with('/') {
            open.push(name.clone());
            if name == "a" {
                href = link(tag).unwrap_or_default();
            }
        }
        let active = |tag: &str| open.iter().any(|open| open == tag);
        style = [active("b"), active("i"), active("u")];
        if !active("a") {
            href.clear();
        }
    }
    if !open.is_empty() {
        return None;
    }
    text.push_str(rest);
    flush(&mut text, style, &href);
    Some(runs)
}

fn entity(name: &str) -> Option<char> {
    match name {
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "quot" => Some('"'),
        "apos" => Some('\''),
        _ => {
            let number = name.strip_prefix('#')?;
            let code = match number.strip_prefix(['x', 'X']) {
                Some(hex) => u32::from_str_radix(hex, 16).ok()?,
                None => number.parse().ok()?,
            };
            char::from_u32(code)
        }
    }
}

/// Only web and mail links open from a notification body.
fn link(tag: &str) -> Option<String> {
    let start = tag.find("href=")? + 5;
    let value = &tag[start..];
    let quote = value.chars().next().filter(|c| *c == '"' || *c == '\'')?;
    let value = &value[1..];
    let href = &value[..value.find(quote)?];
    let href = href.replace("&amp;", "&");
    ["https://", "http://", "mailto:"]
        .iter()
        .any(|scheme| href.to_ascii_lowercase().starts_with(scheme))
        .then_some(href)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(runs: &[NotificationText]) -> String {
        runs.iter().map(|run| run.text.as_str()).collect()
    }

    #[test]
    fn markup_keeps_supported_tags_and_safe_links() {
        let runs = parse_body(
            "Hi <b>bold <i>both</i></b> &amp; <a href=\"https://x.test/?a=1&amp;b\">link</a><br/>end",
        );
        assert_eq!(text(&runs), "Hi bold both & link\nend");
        assert!(
            runs.iter()
                .any(|run| run.bold && run.italic && run.text == "both")
        );
        assert_eq!(
            runs.iter().find(|run| run.text == "link").unwrap().href,
            "https://x.test/?a=1&b"
        );
        let unsafe_link = parse_body("<a href='file:///etc/passwd'>x</a>");
        assert_eq!(unsafe_link[0].href, "");
    }

    #[test]
    fn malformed_markup_falls_back_to_plain_text() {
        for body in ["a < b", "<b>open", "<b>x</i>", "AT&T rocks"] {
            assert_eq!(text(&parse_body(body)), body);
        }
        assert!(parse_body("").is_empty());
    }

    #[test]
    fn images_honor_rowstride_and_downscale() {
        // 2x1 RGB with one padding byte per row.
        let (argb, width, height) =
            decode_pixels(2, 1, 7, false, 8, 3, &[1, 2, 3, 4, 5, 6, 0]).unwrap();
        assert_eq!((width, height), (2, 1));
        assert_eq!(argb, vec![255, 1, 2, 3, 255, 4, 5, 6]);
        assert!(decode_pixels(2, 2, 7, false, 8, 3, &[0; 9]).is_none());
        assert!(decode_pixels(2, 1, 8, true, 8, 3, &[0; 8]).is_none());
        let large = vec![9; 512 * 256 * 4];
        let (_, width, height) = decode_pixels(512, 256, 2048, true, 8, 4, &large).unwrap();
        assert_eq!((width, height), (128, 64));
    }

    #[test]
    fn actions_split_default_and_ignore_odd_tail() {
        let (actions, default_action) = parse_actions(
            ["default", "", "reply", "Reply", "dangling"]
                .map(String::from)
                .to_vec(),
        );
        assert!(default_action);
        assert_eq!(actions.len(), 1);
        assert_eq!(actions[0].label, "Reply");
    }
}
