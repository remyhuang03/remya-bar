<p align="center">
  <img src="../assets/icons/app_icon-full.svg" width="128" alt="Remy'a Bar 图标">
</p>

<h1 align="center">Remy'a Bar</h1>

<h3 align="center">适用于 Arch Linux Hyprland 的多功能状态栏</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License">
</p>

<p align="center">
  <a href="../README.md">English</a> ·
  <strong>简体中文</strong> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.ja.md">日本語</a>
</p>

一款面向 **Linux Hyprland** 的现代化流畅桌面状态栏，基于 **Flutter** 与 **Material Design 3 Expressive** 打造，并由高性能 **Rust** 引擎驱动。视觉灵感源自 [illogical-impulse's Bar](https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii/bar)，提供丰富的状态组件。

> [!WARNING]
> 本软件目前处于 **Beta** 测试阶段，可能存在错误或不稳定情况。相关功能与行为仍在持续完善中。性能优化工作仍在进行中。

<p align="center">
  <video src="images/hero-demo.mp4" controls autoplay loop muted playsinline width="100%"></video>
</p>

## 🚀 安装

`remya-bar` 依赖 **Remya Core**（`remya-core` / `remyad`）提供的 `top.remya.Core1` D-Bus 服务来管理共享主题令牌与配置持久化，请先安装并启用 **Remya Core**，再安装 **Remy'a Bar**（`top.remya.bar.service` 会自动编排在 `top.remya.core.service` 之后启动；**Remya Settings** 为可选的系统级设置前端）。

### 1a. 通过 AUR 安装（推荐）

使用您偏好的 AUR 助手安装 `remya-bar`：

```bash
paru -S remya-bar || yay -S remya-bar
```

### 1b. 从发行版压缩包安装（Linux x86_64）

从 [Releases](https://github.com/remyhuang03/remya-bar/releases) 下载 Linux x86_64 发行版压缩包后，可使用附带的 `tool/install.py` 进行安装：

```bash
# 校验文件哈希
sha256sum -c SHA256SUMS --ignore-missing

# 解压并安装
tar --zstd -xf remya_bar-<version>-linux-x86_64.tar.zst
cd remya_bar-<version>-linux-x86_64
python tool/install.py
```

安装程序会将文件复制到 `~/.local/bin` 与 `XDG_DATA_HOME`，写入并启用 `top.remya.bar.service` systemd 用户单元，并配置状态栏随 `graphical-session.target` 启动（需要用户管理器环境中存在 `WAYLAND_DISPLAY` 和 `HYPRLAND_INSTANCE_SIGNATURE`，例如由 `uwsm` 提供）。重新安装时会自动停止该单元、替换程序包并重启服务。运行 `systemctl --user disable --now top.remya.bar.service` 即可关闭开机自启。

### 2. Hyprland 配置

在您的 Hyprland Lua 配置（如 `~/.config/hypr/hyprland.lua`）中添加以下快捷键绑定（若此前已有绑定可先用 `hl.unbind(...)` 解除）：

```lua
local barShortcutSignal = 'gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.'

-- 切换快捷设置侧边栏
hl.bind(
    "SUPER + A",
    hl.dsp.exec_cmd(barShortcutSignal .. 'ToggleSidebar "$HYPRLAND_INSTANCE_SIGNATURE"')
)

-- 音量与亮度快捷键绑定
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

## ✨ 功能特性

### 状态栏胶囊

<table>
  <tr>
    <th>胶囊</th>
    <th>功能说明</th>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-sidebar.svg" alt="快捷设置开关胶囊" height="34"></td>
    <td><strong>快捷控制入口</strong>：集成网络、蓝牙、音量等状态，点击展开控制中心。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-media.svg" alt="媒体控制胶囊" height="34"></td>
    <td><strong>媒体播放</strong>：显示当前播放曲目，支持一键暂停/继续与切歌。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-clock.svg" alt="时钟胶囊" height="34"></td>
    <td><strong>时钟日期</strong>：精准显示当前时间与日期，点击或悬停可展开日历。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-workspaces.svg" alt="工作区胶囊" height="34"></td>
    <td><strong>工作区切换</strong>：显示各工作区内的应用图标、焦点窗口与紧急提醒。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-resources.svg" alt="系统资源胶囊" height="34"></td>
    <td><strong>系统资源</strong>：实时显示 CPU、内存等系统资源。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-ai-quota.svg" alt="AI 配额胶囊" height="34"></td>
    <td><strong>AI 用量</strong>：直观展示各 AI 订阅的剩余额度与重置时间。</td>
  </tr>
</table>

### 悬停面板与控制中心

<table>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-resources.svg" alt="系统资源监控面板" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-datetime.svg" alt="日期时间面板" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>系统监控</b>：CPU、GPU、内存分配与 60 秒网络波动曲线</sub></td>
    <td align="center"><sub><b>日期时间</b>：大字时钟、世界时间、全年周数与交互式月历</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-media.svg" alt="媒体控制面板" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-battery.svg" alt="电池与电源模式面板" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>媒体控制</b>：随专辑封面自动变色，支持进度拖动与音量调节</sub></td>
    <td align="center"><sub><b>电池电源</b>：电量、功耗、健康度、循环次数与性能模式切换</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-ai-quota.svg" alt="AI 用量统计面板" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-sidebar.svg" alt="快捷设置控制中心" width="97%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>AI 用量</b>：多平台会话/周额度、重置倒计时与每日消费统计</sub></td>
    <td align="center"><sub><b>快捷设置</b>：系统快捷设置与实用小工具快捷方式</sub></td>
  </tr>
</table>

### 屏幕弹窗反馈（OSD）

<table>
  <tr>
    <td width="45%" align="center">
      <img src="images/demo-osd.svg" alt="屏幕弹窗反馈 OSD" width="280">
    </td>
    <td>
      <ul>
        <li><strong>音量与增益</strong>：调节音量或开启超限增益时，顶部居中弹出实时进度胶囊。</li>
        <li><strong>亮度与软件调光</strong>：支持硬件背光与软件亮度调节提示，清晰区分当前模式。</li>
        <li><strong>通知与勿扰</strong>：集中记录错过的桌面通知，支持一键清空与勿扰模式开关。</li>
      </ul>
    </td>
  </tr>
</table>

## ⌨️ 开发

### 技术栈与架构

- **Flutter**：通过 FVM 固定使用 `3.47.9`，搭配 Material Design 3 Expressive（`material_ui`）。
- **Rust**：`2024` edition，使用根目录 `rust-toolchain.toml` 作为 Cargo 工作区进行管理。
- **FFI**：通过 `flutter_rust_bridge` 将 `remya_bar_hyprland` 和 `remya_bar_system` 桥接至 Flutter。
- **Wayland**：原生 GTK 运行时动态链接 `gtk-layer-shell`，用于实现逐显示器状态栏窗口、`BarPopup` 浮动宿主以及 `--settings` 独立设置窗口。
- **Core 集成**：通过会话 D-Bus（`top.remya.Core1`）接入 `remya-core` 提供的 `remya_client` 与 `remya_ui` 包，管理共享主题与原子化偏好持久化。契约详情请参阅 [docs/backend.md](backend.md)。

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

- **目录结构**：
  - `lib/main.dart` 与 `lib/app.dart`：应用启动与根组件组装。
  - `lib/features/`：按功能模块划分的 Flutter UI、状态与控制器。
  - `lib/src/rust/`：模块化 Rust crate（`hyprland`、`system`、`core` 及生成的桥接 crate）。
  - `linux/`：原生 GTK 运行时、`gtk-layer-shell` 配置及桌面打包脚本。
  - `assets/icons/`：应用图标与功能图标。
  - `tool/install.py`：XDG 安装与 systemd 用户服务辅助脚本。

### 环境要求与配置

- 安装了 Flutter SDK `3.47.9` 的 FVM
- 通过 `rustup` 管理的 Rust 工具链（`2024` edition）
- 开发期需要同级目录 `../remya-core` 检出，用于提供 `packages/remya_client` 与 `packages/remya_ui`（编译后的发行版包无需同级源码检出）
- 运行时需安装并启用 **Remya Core**（提供 `dbus-1/services/top.remya.Core1.service` 与 `top.remya.core.service`）
- Arch Linux 运行时与原生构建依赖：

| 依赖项 | 用途 |
| :--- | :--- |
| `gtk-layer-shell`, `wayland`, `libxkbcommon`, `wayland-protocols` | Wayland layer-shell 表面、输入处理及 `wayland-scanner` |
| `sqlite` | 持久化通知历史记录 |
| `inter-font`, `noto-fonts-cjk` | 系统排版字体与中日韩字符回退 |
| `networkmanager`, `bluez` | 网络与蓝牙快捷设置开关 |
| `nvidia-utils` *（可选）* | 提供 `libnvidia-ml.so.1` 以采集 NVIDIA GPU 指标 |
| `codexbar-cli` *（可选）* | 提供 `codexbar` 可执行文件以获取 AI 配额 |

```bash
fvm install
fvm flutter pub get
```

修改 Rust 桥接 API 后，请使用 `flutter_rust_bridge_codegen` 和 `flutter_rust_bridge.yaml` 重新生成绑定代码。

### 验证与本地安装

```bash
# Dart 格式化、静态分析与测试
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Rust 格式化、Lint 检查与测试
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Linux 调试构建与原生生命周期 / 冒烟测试
fvm flutter build linux --debug
cmake --build build/linux/x64/debug --target bar_lifecycle_test
build/linux/x64/debug/bundle/bar_lifecycle_test
python test/bar_window_smoke.py  # 需要正在运行的 Hyprland 会话

# 发布构建并安装到本地 XDG 目录
fvm flutter build linux --release
python tool/install.py
```

## 📜 许可证

本项目基于 [PolyForm Noncommercial License 1.0.0](../LICENSE) 许可证发布。
