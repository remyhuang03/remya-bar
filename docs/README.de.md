<p align="center">
  <img src="../assets/icons/app_icon-full.svg" width="128" alt="Remy'a Bar Symbol">
</p>

<h1 align="center">Remy'a Bar</h1>

<h3 align="center">Eine vielseitige Statusleiste für Arch Linux Hyprland</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License">
</p>

<p align="center">
  <a href="../README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ru.md">Русский</a> ·
  <strong>Deutsch</strong> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.ja.md">日本語</a>
</p>

Eine moderne, flüssige Desktop-Statusleiste für **Linux Hyprland**, entwickelt mit **Flutter** und **Material Design 3 Expressive**, angetrieben von einer leistungsstarken **Rust**-Engine. Visuell inspiriert von [illogical-impulse's Bar](https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii/bar), bietet sie eine Vielzahl von Status-Widgets.

> [!WARNING]
> Diese Software befindet sich derzeit in der **Beta**-Phase und kann Fehler oder Instabilitäten enthalten. Funktionen und Verhalten werden noch verfeinert, und die Leistungsoptimierung läuft noch.

<p align="center">
  <video src="images/hero-demo.mp4" controls autoplay loop muted playsinline width="100%"></video>
</p>

## 🚀 Installation

`remya-bar` hängt vom D-Bus-Dienst `top.remya.Core1` ab, der von **Remya Core** (`remya-core` / `remyad`) bereitgestellt wird, um gemeinsame Theme-Tokens und die Konfigurationspersistenz zu verwalten. Bitte installiere und aktiviere zuerst **Remya Core**, bevor du **Remy'a Bar** installierst (`top.remya.bar.service` wird automatisch so geordnet, dass es nach `top.remya.core.service` startet; **Remya Settings** ist ein optionales Frontend für Systemeinstellungen).

### 1a. Installation über AUR (Empfohlen)

Installiere `remya-bar` mit deinem bevorzugten AUR-Helper:

```bash
paru -S remya-bar || yay -S remya-bar
```

### 1b. Installation aus dem Release-Archiv (Linux x86_64)

Nach dem Herunterladen des Linux-x86_64-Release-Archivs von [Releases](https://github.com/remyhuang03/remya-bar/releases) kannst du es mit dem mitgelieferten `tool/install.py` installieren:

```bash
# Datei-Prüfsumme verifizieren
sha256sum -c SHA256SUMS --ignore-missing

# Entpacken und installieren
tar --zstd -xf remya_bar-<version>-linux-x86_64.tar.zst
cd remya_bar-<version>-linux-x86_64
python tool/install.py
```

Das Installationsskript kopiert die Dateien nach `~/.local/bin` und `XDG_DATA_HOME`, schreibt und aktiviert die systemd-Benutzereinheit `top.remya.bar.service` und konfiguriert die Leiste für den Start mit `graphical-session.target` (erfordert `WAYLAND_DISPLAY` und `HYPRLAND_INSTANCE_SIGNATURE` in der Umgebung des Benutzermanagers, z. B. durch `uwsm` bereitgestellt). Bei einer Neuinstallation wird die Einheit automatisch gestoppt, das Paket ersetzt und der Dienst neu gestartet. Führe `systemctl --user disable --now top.remya.bar.service` aus, um den Autostart zu deaktivieren.

### 2. Hyprland-Konfiguration

Füge folgende Tastenkürzel in deine Hyprland-Lua-Konfiguration (z. B. `~/.config/hypr/hyprland.lua`) ein (falls bereits Belegungen vorhanden sind, kannst du sie zuvor mit `hl.unbind(...)` aufheben):

```lua
local barShortcutSignal = 'gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.'

-- Schnelleinstellungen-Seitenleiste umschalten
hl.bind(
    "SUPER + A",
    hl.dsp.exec_cmd(barShortcutSignal .. 'ToggleSidebar "$HYPRLAND_INSTANCE_SIGNATURE"')
)

-- Lautstärke- und Helligkeits-Tastenkürzel
hl.bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd(barShortcutSignal .. 'VolumeUp "$HYPRLAND_INSTANCE_SIGNATURE"'),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd(barShortcutSignal .. 'VolumeDown "$HYPRLAND_INSTANCE_SIGNATURE"'),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioMute",
    hl.dsp.exec_cmd(barShortcutSignal .. 'VolumeMute "$HYPRLAND_INSTANCE_SIGNATURE"'),
    { locked = true }
)
hl.bind(
    "XF86MonBrightnessUp",
    hl.dsp.exec_cmd(barShortcutSignal .. 'BrightnessUp "$HYPRLAND_INSTANCE_SIGNATURE"'),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86MonBrightnessDown",
    hl.dsp.exec_cmd(barShortcutSignal .. 'BrightnessDown "$HYPRLAND_INSTANCE_SIGNATURE"'),
    { locked = true, repeating = true }
)
```

## ✨ Funktionen

### Statusleisten-Pills

<table>
  <tr>
    <th>Pill</th>
    <th>Beschreibung</th>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-sidebar.svg" alt="Schnelleinstellungen-Umschalt-Pill" height="34"></td>
    <td><strong>Schnellzugriff</strong>: Bündelt Netzwerk-, Bluetooth-, Lautstärke- und weitere Statusanzeigen; ein Klick öffnet das Kontrollzentrum.</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-media.svg" alt="Mediensteuerungs-Pill" height="34"></td>
    <td><strong>Medienwiedergabe</strong>: Zeigt den aktuellen Titel an und unterstützt Wiedergabe/Pause sowie Titelwechsel mit einem Klick.</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-clock.svg" alt="Uhr-Pill" height="34"></td>
    <td><strong>Uhr &amp; Datum</strong>: Zeigt Uhrzeit und Datum präzise an; Klick oder Hover öffnet den Kalender.</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-workspaces.svg" alt="Arbeitsbereiche-Pill" height="34"></td>
    <td><strong>Arbeitsbereichswechsel</strong>: Zeigt App-Symbole, fokussierte Fenster und dringende Hinweise pro Arbeitsbereich.</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-resources.svg" alt="Systemressourcen-Pill" height="34"></td>
    <td><strong>Systemressourcen</strong>: Zeigt CPU-, Arbeitsspeicher- und weitere Systemmetriken in Echtzeit.</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-ai-quota.svg" alt="KI-Kontingent-Pill" height="34"></td>
    <td><strong>KI-Nutzung</strong>: Visualisiert übersichtlich verbleibende Kontingente und Reset-Zeiten von KI-Abonnements.</td>
  </tr>
</table>

### Hover-Panels & Kontrollzentrum

<table>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-resources.svg" alt="Systemressourcen-Panel" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-datetime.svg" alt="Datums- und Zeit-Panel" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>Systemmonitor</b>: CPU, GPU, Speicherbelegung und 60-Sekunden-Netzwerkverlaufsdiagramme</sub></td>
    <td align="center"><sub><b>Datum &amp; Uhrzeit</b>: Große Uhr, Weltzeit, Kalenderwoche und interaktiver Monatskalender</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-media.svg" alt="Mediensteuerungs-Panel" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-battery.svg" alt="Akku- und Energiemodus-Panel" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>Mediensteuerung</b>: Adaptive Farben vom Albumcover, Fortschrittsregler und Lautstärkeregler</sub></td>
    <td align="center"><sub><b>Akku &amp; Energie</b>: Ladestand, Leistungsaufnahme, Akkugesundheit, Ladezyklen und Leistungsmodus-Umschaltung</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-ai-quota.svg" alt="KI-Nutzungsstatistik-Panel" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-sidebar.svg" alt="Schnelleinstellungen-Kontrollzentrum" width="97%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>KI-Nutzung</b>: Plattformübergreifende Sitzungs-/Wochenkontingente, Reset-Countdowns und Tagesverbrauch</sub></td>
    <td align="center"><sub><b>Schnelleinstellungen</b>: Systemschnellschalter und praktische Werkzeug-Verknüpfungen</sub></td>
  </tr>
</table>

### On-Screen-Display (OSD)

<table>
  <tr>
    <td width="45%" align="center">
      <img src="images/demo-osd.svg" alt="On-Screen-Display OSD" width="280">
    </td>
    <td>
      <ul>
        <li><strong>Lautstärke &amp; Boost</strong>: Blendet beim Anpassen der Lautstärke oder Aktivieren des Overdrive-Boosts oben zentriert eine Live-Fortschrittskapsel ein.</li>
        <li><strong>Helligkeit &amp; Software-Dimming</strong>: Unterstützt Hinweise für Hardware-Hintergrundbeleuchtung und Software-Helligkeit mit klarer Unterscheidung des aktiven Modus.</li>
        <li><strong>Benachrichtigungen &amp; Bitte nicht stören</strong>: Sammelt verpasste Desktop-Benachrichtigungen zentral mit Ein-Klick-Löschung und „Bitte nicht stören“-Schalter.</li>
      </ul>
    </td>
  </tr>
</table>

## ⌨️ Entwicklung

### Tech-Stack & Architektur

- **Flutter**: Über FVM auf `3.47.9` fixiert, kombiniert mit Material Design 3 Expressive (`material_ui`).
- **Rust**: `2024` Edition, verwaltet als Cargo-Workspace mit der `rust-toolchain.toml` im Stammverzeichnis.
- **FFI**: Bindet `remya_bar_hyprland` und `remya_bar_system` über `flutter_rust_bridge` an Flutter an.
- **Wayland**: Nativer GTK-Runner mit dynamisch gelinktem `gtk-layer-shell` für Statusleistenfenster pro Monitor, schwebende `BarPopup`-Hosts sowie das eigenständige `--settings`-Fenster.
- **Core-Integration**: Verbindet sich über Sitzungs-D-Bus (`top.remya.Core1`) mit den von `remya-core` bereitgestellten Paketen `remya_client` und `remya_ui` zur Verwaltung gemeinsamer Themes und atomarer Einstellungs-Persistenz. Vertragsdetails siehe [docs/backend.md](backend.md).

```
┌────────────────────────────────────────────────────────┐
│                   Flutter UI Layer                     │
│  - MD3 Expressive widgets & spring animations          │
│  - Per-monitor GTK Layer-Shell views                   │
│  - Floating popup host (BarPopup) & --settings window  │
└───────────────────────────▲────────────────────────────┘
                            │ flutter_rust_bridge
┌───────────────────────────▼────────────────────────────┐
│                    Rust Workspace                      │
│  - remya_bar_hyprland: Tokio Unix socket IPC & events  │
│  - remya_bar_system: Cached /proc, sysfs, GPU & MPRIS  │
│  - System tray SNI host & DBusMenu client              │
└───────────────────────────▲────────────────────────────┘
                            │ D-Bus (top.remya.Core1)
┌───────────────────────────▼────────────────────────────┐
│                   Remya Core (remyad)                  │
│  - Shared theme tokens, system settings & preferences  │
└────────────────────────────────────────────────────────┘
```

- **Verzeichnisstruktur**:
  - `lib/main.dart` und `lib/app.dart`: Anwendungsstart und Wurzel-Widget-Aufbau.
  - `lib/features/`: Nach Funktionsmodulen gegliederte Flutter-UI, Zustände und Controller.
  - `lib/src/rust/`: Modulare Rust-Crates (`hyprland`, `system`, `core` und generierte Bridge-Crates).
  - `linux/`: Nativer GTK-Runner, `gtk-layer-shell`-Konfiguration und Desktop-Paketierungsskripte.
  - `assets/icons/`: App-Symbol und Funktionssymbole.
  - `tool/install.py`: XDG-Installations- und systemd-Benutzerdienst-Hilfsskript.

### Voraussetzungen & Einrichtung

- FVM mit installiertem Flutter SDK `3.47.9`
- Über `rustup` verwaltete Rust-Toolchain (`2024` Edition)
- Während der Entwicklung ist ein benachbarter `../remya-core`-Checkout für `packages/remya_client` und `packages/remya_ui` erforderlich (kompilierte Release-Pakete benötigen keinen benachbarten Quellcode-Checkout)
- Zur Laufzeit muss **Remya Core** installiert und aktiviert sein (stellt `dbus-1/services/top.remya.Core1.service` und `top.remya.core.service` bereit)
- Laufzeit- und native Build-Abhängigkeiten unter Arch Linux:

| Abhängigkeit | Zweck |
| :--- | :--- |
| `gtk-layer-shell`, `wayland`, `libxkbcommon`, `wayland-protocols` | Wayland-Layer-Shell-Oberflächen, Eingabeverarbeitung und `wayland-scanner` |
| `sqlite` | Persistenter Benachrichtigungsverlauf |
| `inter-font`, `noto-fonts-cjk` | Systemtypografie und CJK-Fallback |
| `networkmanager`, `bluez` | Netzwerk- und Bluetooth-Schalter in den Schnelleinstellungen |
| `nvidia-utils` *(optional)* | Stellt `libnvidia-ml.so.1` für NVIDIA-GPU-Metriken bereit |
| `codexbar-cli` *(optional)* | Stellt `codexbar`-Programm für KI-Kontingente bereit |

```bash
fvm install
fvm flutter pub get
```

Nach Änderungen an einer Rust-Bridge-API müssen die Bindings mit `flutter_rust_bridge_codegen` und `flutter_rust_bridge.yaml` neu generiert werden.

### Validierung & lokale Installation

```bash
# Dart-Formatierung, statische Analyse und Tests
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Rust-Formatierung, Lints und Tests
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Linux-Debug-Build und native Lebenszyklus- / Smoke-Tests
fvm flutter build linux --debug
cmake --build build/linux/x64/debug --target bar_lifecycle_test
build/linux/x64/debug/bundle/bar_lifecycle_test
python test/bar_window_smoke.py  # Erfordert eine laufende Hyprland-Sitzung

# Release-Build und Installation in lokale XDG-Verzeichnisse
fvm flutter build linux --release
python tool/install.py
```

## 📜 Lizenz

Dieses Projekt steht unter der [PolyForm Noncommercial License 1.0.0](../LICENSE).