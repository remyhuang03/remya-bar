<p align="center">
  <img src="../assets/icons/app_icon-full.svg" width="128" alt="Remy'a Bar 圖示">
</p>

<h1 align="center">Remy'a Bar</h1>

<h3 align="center">適用於 Arch Linux Hyprland 的多功能狀態列</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License">
</p>

<p align="center">
  <a href="../README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <strong>繁體中文</strong> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.ja.md">日本語</a>
</p>

一款面向 **Linux Hyprland** 的現代化流暢桌面狀態列，基於 **Flutter** 與 **Material Design 3 Expressive** 打造，並由高效能 **Rust** 引擎驅動。視覺靈感源自 [illogical-impulse's Bar](https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii/bar)，提供豐富的狀態元件。

> [!WARNING]
> 本軟體目前處於 **Beta** 測試階段，可能存在錯誤或不穩定情況。相關功能與行為仍在持續完善中，效能最佳化工作亦在進行中。

<p align="center">
  <video src="images/hero-demo.mp4" controls autoplay loop muted playsinline width="100%"></video>
</p>

## 🚀 安裝

`remya-bar` 依賴 **Remya Core**（`remya-core` / `remyad`）提供的 `top.remya.Core1` D-Bus 服務來管理共享主題權杖與設定持久化，請先安裝並啟用 **Remya Core**，再安裝 **Remy'a Bar**（`top.remya.bar.service` 會自動編排在 `top.remya.core.service` 之後啟動；**Remya Settings** 為可選的系統級設定前端）。

### 1a. 透過 AUR 安裝（推薦）

使用您偏好的 AUR 助手安裝 `remya-bar`：

```bash
paru -S remya-bar || yay -S remya-bar
```

### 1b. 從發行版壓縮檔安裝（Linux x86_64）

從 [Releases](https://github.com/remyhuang03/remya-bar/releases) 下載 Linux x86_64 發行版壓縮檔後，可使用隨附的 `tool/install.py` 進行安裝：

```bash
# 校驗檔案雜湊
sha256sum -c SHA256SUMS --ignore-missing

# 解壓縮並安裝
tar --zstd -xf remya_bar-<version>-linux-x86_64.tar.zst
cd remya_bar-<version>-linux-x86_64
python tool/install.py
```

安裝程式會將檔案複製到 `~/.local/bin` 與 `XDG_DATA_HOME`，寫入並啟用 `top.remya.bar.service` systemd 使用者單元，並設定狀態列隨 `graphical-session.target` 啟動（需要使用者管理員環境中存在 `WAYLAND_DISPLAY` 和 `HYPRLAND_INSTANCE_SIGNATURE`，例如由 `uwsm` 提供）。重新安裝時會自動停止該單元、替換程式套件並重啟服務。執行 `systemctl --user disable --now top.remya.bar.service` 即可關閉開機自啟。

### 2. Hyprland 設定

在您的 Hyprland Lua 設定（如 `~/.config/hypr/hyprland.lua`）中加入以下快捷鍵綁定（若此前已有綁定可先用 `hl.unbind(...)` 解除）：

```lua
local barShortcutSignal = 'gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.'

-- 切換快速設定側邊欄
hl.bind(
    "SUPER + A",
    hl.dsp.exec_cmd(barShortcutSignal .. 'ToggleSidebar "$HYPRLAND_INSTANCE_SIGNATURE"')
)

-- 音量與亮度快捷鍵綁定
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

## ✨ 功能特色

### 狀態列膠囊

<table>
  <tr>
    <th>膠囊</th>
    <th>功能說明</th>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-sidebar.svg" alt="快速設定開關膠囊" height="34"></td>
    <td><strong>快速控制入口</strong>：整合網路、藍牙、音量等狀態，點擊展開控制中心。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-media.svg" alt="媒體控制膠囊" height="34"></td>
    <td><strong>媒體播放</strong>：顯示目前播放曲目，支援一鍵暫停／繼續與切換歌曲。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-clock.svg" alt="時鐘膠囊" height="34"></td>
    <td><strong>時鐘日期</strong>：精準顯示目前時間與日期，點擊或懸停可展開行事曆。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-workspaces.svg" alt="工作區膠囊" height="34"></td>
    <td><strong>工作區切換</strong>：顯示各工作區內的應用程式圖示、焦點視窗與緊急提醒。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-resources.svg" alt="系統資源膠囊" height="34"></td>
    <td><strong>系統資源</strong>：即時顯示 CPU、記憶體等系統資源。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-ai-quota.svg" alt="AI 配額膠囊" height="34"></td>
    <td><strong>AI 用量</strong>：直覺展示各 AI 訂閱的剩餘額度與重設時間。</td>
  </tr>
</table>

### 懸停面板與控制中心

<table>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-resources.svg" alt="系統資源監控面板" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-datetime.svg" alt="日期時間面板" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>系統監控</b>：CPU、GPU、記憶體分配與 60 秒網路波動曲線</sub></td>
    <td align="center"><sub><b>日期時間</b>：大字時鐘、世界時間、全年週數與互動式月曆</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-media.svg" alt="媒體控制面板" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-battery.svg" alt="電池與電源模式面板" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>媒體控制</b>：隨專輯封面自動變色，支援進度拖曳與音量調整</sub></td>
    <td align="center"><sub><b>電池電源</b>：電量、功耗、健康度、循環次數與效能模式切換</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-ai-quota.svg" alt="AI 用量統計面板" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-sidebar.svg" alt="快速設定控制中心" width="97%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>AI 用量</b>：多平台工作階段／週額度、重設倒數計時與每日消費統計</sub></td>
    <td align="center"><sub><b>快速設定</b>：系統快速設定與實用小工具捷徑</sub></td>
  </tr>
</table>

### 螢幕彈窗回饋（OSD）

<table>
  <tr>
    <td width="45%" align="center">
      <img src="images/demo-osd.svg" alt="螢幕彈窗回饋 OSD" width="280">
    </td>
    <td>
      <ul>
        <li><strong>音量與增益</strong>：調整音量或開啟超限增益時，頂部置中彈出即時進度膠囊。</li>
        <li><strong>亮度與軟體調光</strong>：支援硬體背光與軟體亮度調整提示，清晰區分目前模式。</li>
        <li><strong>通知與勿擾</strong>：集中記錄錯過的桌面通知，支援一鍵清空與勿擾模式開關。</li>
      </ul>
    </td>
  </tr>
</table>

## ⌨️ 開發

### 技術棧與架構

- **Flutter**：透過 FVM 固定使用 `3.47.9`，搭配 Material Design 3 Expressive（`material_ui`）。
- **Rust**：`2024` edition，使用根目錄 `rust-toolchain.toml` 作為 Cargo 工作區進行管理。
- **FFI**：透過 `flutter_rust_bridge` 將 `remya_bar_hyprland` 和 `remya_bar_system` 橋接至 Flutter。
- **Wayland**：原生 GTK 執行時期動態連結 `gtk-layer-shell`，用於實作逐顯示器狀態列視窗、`BarPopup` 浮動宿主以及 `--settings` 獨立設定視窗。
- **Core 整合**：透過工作階段 D-Bus（`top.remya.Core1`）接入 `remya-core` 提供的 `remya_client` 與 `remya_ui` 套件，管理共享主題與原子化偏好持久化。契約詳情請參閱 [docs/backend.md](backend.md)。

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

- **目錄結構**：
  - `lib/main.dart` 與 `lib/app.dart`：應用程式啟動與根元件組裝。
  - `lib/features/`：依功能模組劃分的 Flutter UI、狀態與控制器。
  - `lib/src/rust/`：模組化 Rust crate（`hyprland`、`system`、`core` 及產生的橋接 crate）。
  - `linux/`：原生 GTK 執行時期、`gtk-layer-shell` 設定及桌面打包腳本。
  - `assets/icons/`：應用程式圖示與功能圖示。
  - `tool/install.py`：XDG 安裝與 systemd 使用者服務輔助腳本。

### 環境需求與設定

- 安裝了 Flutter SDK `3.47.9` 的 FVM
- 透過 `rustup` 管理的 Rust 工具鏈（`2024` edition）
- 開發期需要同層目錄 `../remya-core` 檢出，用於提供 `packages/remya_client` 與 `packages/remya_ui`（編譯後的發行版套件無需同層原始碼檢出）
- 執行時期需安裝並啟用 **Remya Core**（提供 `dbus-1/services/top.remya.Core1.service` 與 `top.remya.core.service`）
- Arch Linux 執行時期與原生建置相依套件：

| 相依套件 | 用途 |
| :--- | :--- |
| `gtk-layer-shell`, `wayland`, `libxkbcommon`, `wayland-protocols` | Wayland layer-shell 表面、輸入處理及 `wayland-scanner` |
| `sqlite` | 持久化通知歷史紀錄 |
| `inter-font`, `noto-fonts-cjk` | 系統排版字型與中日韓字元回退 |
| `networkmanager`, `bluez` | 網路與藍牙快速設定開關 |
| `nvidia-utils` *（可選）* | 提供 `libnvidia-ml.so.1` 以擷取 NVIDIA GPU 指標 |
| `codexbar-cli` *（可選）* | 提供 `codexbar` 可執行檔以取得 AI 配額 |

```bash
fvm install
fvm flutter pub get
```

修改 Rust 橋接 API 後，請使用 `flutter_rust_bridge_codegen` 和 `flutter_rust_bridge.yaml` 重新產生繫結程式碼。

### 驗證與本地安裝

```bash
# Dart 格式化、靜態分析與測試
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Rust 格式化、Lint 檢查與測試
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Linux 除錯建置與原生生命週期／冒煙測試
fvm flutter build linux --debug
cmake --build build/linux/x64/debug --target bar_lifecycle_test
build/linux/x64/debug/bundle/bar_lifecycle_test
python test/bar_window_smoke.py  # 需要正在執行的 Hyprland 工作階段

# 發行建置並安裝到本地 XDG 目錄
fvm flutter build linux --release
python tool/install.py
```

## 📜 授權條款

本專案基於 [PolyForm Noncommercial License 1.0.0](../LICENSE) 授權條款釋出。