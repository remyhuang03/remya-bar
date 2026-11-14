<p align="center">
  <img src="../assets/icons/app_icon-full.svg" width="128" alt="Remy'a Bar アイコン">
</p>

<h1 align="center">Remy'a Bar</h1>

<h3 align="center">Arch Linux Hyprland 向けの多機能ステータスバー</h3>

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
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <strong>日本語</strong>
</p>

**Linux Hyprland** 向けのモダンで滑らかなデスクトップステータスバーです。**Flutter** と **Material Design 3 Expressive** で構築され、高性能な **Rust** エンジンによって支えられています。[illogical-impulse's Bar](https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii/bar) からビジュアルの着想を得ており、豊富なステータスウィジェットを提供します。

> [!WARNING]
> このソフトウェアは現在 **ベータ版** であり、バグや不安定な動作が含まれる可能性があります。機能や挙動は引き続き改善されており、パフォーマンスの最適化も進行中です。

<p align="center">
  <video src="images/hero-demo.mp4" controls autoplay loop muted playsinline width="100%"></video>
</p>

## 🚀 インストール

`remya-bar` は、共有テーマトークンと設定の永続化を管理するために **Remya Core**（`remya-core` / `remyad`）が提供する `top.remya.Core1` D-Bus サービスに依存しています。**Remy'a Bar** をインストールする前に、まず **Remya Core** をインストールして有効化してください（`top.remya.bar.service` は `top.remya.core.service` の後に起動するよう自動構成されます。**Remya Settings** はオプションのシステム設定フロントエンドです）。

### 1a. AUR からインストール（推奨）

お好みの AUR ヘルパーを使用して `remya-bar` をインストールします：

```bash
paru -S remya-bar || yay -S remya-bar
```

### 1b. リリースアーカイブからインストール（Linux x86_64）

[Releases](https://github.com/remyhuang03/remya-bar/releases) から Linux x86_64 リリースアーカイブをダウンロードした後、同梱の `tool/install.py` を使用してインストールできます：

```bash
# ファイルハッシュを検証
sha256sum -c SHA256SUMS --ignore-missing

# 展開してインストール
tar --zstd -xf remya_bar-<version>-linux-x86_64.tar.zst
cd remya_bar-<version>-linux-x86_64
python tool/install.py
```

インストーラーはファイルを `~/.local/bin` と `XDG_DATA_HOME` にコピーし、`top.remya.bar.service` systemd ユーザーユニットを書き込んで有効化し、`graphical-session.target` とともにバーが起動するよう設定します（ユーザーマネージャー環境に `uwsm` などから提供される `WAYLAND_DISPLAY` と `HYPRLAND_INSTANCE_SIGNATURE` が必要です）。再インストール時はユニットを自動停止し、バンドルを置き換えてサービスを再起動します。自動起動を無効にするには `systemctl --user disable --now top.remya.bar.service` を実行してください。

### 2. Hyprland の設定

Hyprland の Lua 設定（例：`~/.config/hypr/hyprland.lua`）に以下のキーバインドを追加してください（既存のバインドがある場合は先に `hl.unbind(...)` で解除できます）：

```lua
local barShortcutSignal = 'gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.'

-- クイック設定サイドバーの切り替え
hl.bind(
    "SUPER + A",
    hl.dsp.exec_cmd(barShortcutSignal .. 'ToggleSidebar "$HYPRLAND_INSTANCE_SIGNATURE"')
)

-- 音量・輝度のキーバインド
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

## ✨ 機能

### ステータスバーピル

<table>
  <tr>
    <th>ピル</th>
    <th>機能説明</th>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-sidebar.svg" alt="クイック設定切り替えピル" height="34"></td>
    <td><strong>クイックコントロール入口</strong>：ネットワーク、Bluetooth、音量などのステータスを統合し、クリックでコントロールセンターを展開します。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-media.svg" alt="メディアコントロールピル" height="34"></td>
    <td><strong>メディア再生</strong>：現在再生中のトラックを表示し、ワンクリックでの再生／一時停止や曲送りに対応します。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-clock.svg" alt="時計ピル" height="34"></td>
    <td><strong>時計・日付</strong>：現在時刻と日付を正確に表示し、クリックまたはホバーでカレンダーを展開します。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-workspaces.svg" alt="ワークスペースピル" height="34"></td>
    <td><strong>ワークスペース切り替え</strong>：各ワークスペース内のアプリアイコン、フォーカス中のウィンドウ、緊急通知を表示します。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-resources.svg" alt="システムリソースピル" height="34"></td>
    <td><strong>システムリソース</strong>：CPU、メモリなどのシステムリソースをリアルタイムに表示します。</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-ai-quota.svg" alt="AI クォータピル" height="34"></td>
    <td><strong>AI 使用量</strong>：各 AI サブスクリプションの残りクォータとリセット時刻を分かりやすく表示します。</td>
  </tr>
</table>

### ホバーパネル＆コントロールセンター

<table>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-resources.svg" alt="システムリソースモニターパネル" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-datetime.svg" alt="日時パネル" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>システムモニター</b>：CPU、GPU、メモリ割り当てと 60 秒間のネットワーク変動グラフ</sub></td>
    <td align="center"><sub><b>日時</b>：大型時計、世界時計、年間週数とインタラクティブ月間カレンダー</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-media.svg" alt="メディアコントロールパネル" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-battery.svg" alt="バッテリー・電源モードパネル" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>メディアコントロール</b>：アルバムアート連動カラー、シークバー、音量調整に対応</sub></td>
    <td align="center"><sub><b>バッテリー・電源</b>：残量、消費電力、バッテリー健康度、サイクル数、パフォーマンスモード切り替え</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-ai-quota.svg" alt="AI 使用量統計パネル" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-sidebar.svg" alt="クイック設定コントロールセンター" width="97%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>AI 使用量</b>：複数プラットフォームのセッション／週間クォータ、リセットカウントダウン、日次消費統計</sub></td>
    <td align="center"><sub><b>クイック設定</b>：システムクイック設定と便利なユーティリティショートカット</sub></td>
  </tr>
</table>

### オンスクリーンディスプレイ（OSD）

<table>
  <tr>
    <td width="45%" align="center">
      <img src="images/demo-osd.svg" alt="オンスクリーンディスプレイ OSD" width="280">
    </td>
    <td>
      <ul>
        <li><strong>音量とブースト</strong>：音量の調整やオーバーブースト有効化時に、画面上部中央へリアルタイムの進捗カプセルを表示します。</li>
        <li><strong>輝度とソフトウェア調光</strong>：ハードウェアバックライトとソフトウェア輝度調整の両方に対応し、現在のモードを明確に区別して表示します。</li>
        <li><strong>通知とおやすみモード</strong>：見逃したデスクトップ通知を一元記録し、ワンクリックでの全消去とおやすみモードの切り替えに対応します。</li>
      </ul>
    </td>
  </tr>
</table>

## ⌨️ 開発

### 技術スタック＆アーキテクチャ

- **Flutter**：FVM により `3.47.9` に固定し、Material Design 3 Expressive（`material_ui`）を組み合わせています。
- **Rust**：`2024` edition、ルートの `rust-toolchain.toml` を用いて Cargo ワークスペースとして管理されています。
- **FFI**：`flutter_rust_bridge` を介して `remya_bar_hyprland` と `remya_bar_system` を Flutter にブリッジします。
- **Wayland**：ネイティブ GTK ランタイムが `gtk-layer-shell` を動的リンクし、モニターごとのステータスバーウィンドウ、`BarPopup` フローティングホスト、および `--settings` 独立設定ウィンドウを実現しています。
- **Core 連携**：セッション D-Bus（`top.remya.Core1`）経由で `remya-core` が提供する `remya_client` および `remya_ui` パッケージに接続し、共有テーマとアトミックな設定永続化を管理します。コントラクトの詳細は [docs/backend.md](backend.md) を参照してください。

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

- **ディレクトリ構成**：
  - `lib/main.dart` と `lib/app.dart`：アプリケーションの起動とルートウィジェットの構成。
  - `lib/features/`：機能モジュールごとに分割された Flutter UI、状態管理、コントローラー。
  - `lib/src/rust/`：モジュール化された Rust クレート（`hyprland`、`system`、`core`、および生成されたブリッジクレート）。
  - `linux/`：ネイティブ GTK ランタイム、`gtk-layer-shell` 設定、デスクトップパッケージングスクリプト。
  - `assets/icons/`：アプリアイコンおよび機能アイコン。
  - `tool/install.py`：XDG インストールおよび systemd ユーザーサービス補助スクリプト。

### 前提条件とセットアップ

- Flutter SDK `3.47.9` をインストール済みの FVM
- `rustup` で管理された Rust ツールチェイン（`2024` edition）
- 開発時は `packages/remya_client` と `packages/remya_ui` を提供するために同階層の `../remya-core` チェックアウトが必要（ビルド済みのリリースバンドルでは同階層のソースチェックアウトは不要）
- 実行時は **Remya Core** のインストールと有効化が必要（`dbus-1/services/top.remya.Core1.service` および `top.remya.core.service` を提供）
- Arch Linux のランタイムおよびネイティブビルド依存関係：

| 依存関係 | 用途 |
| :--- | :--- |
| `gtk-layer-shell`, `wayland`, `libxkbcommon`, `wayland-protocols` | Wayland layer-shell サーフェス、入力処理、および `wayland-scanner` |
| `sqlite` | 通知履歴の永続化 |
| `inter-font`, `noto-fonts-cjk` | システムタイポグラフィおよび CJK フォールバック |
| `networkmanager`, `bluez` | ネットワークおよび Bluetooth のクイック設定トグル |
| `nvidia-utils` *（オプション）* | NVIDIA GPU メトリクス取得用の `libnvidia-ml.so.1` を提供 |
| `codexbar-cli` *（オプション）* | AI クォータ取得用の `codexbar` 実行ファイルを提供 |

```bash
fvm install
fvm flutter pub get
```

Rust ブリッジ API を変更した後は、`flutter_rust_bridge_codegen` と `flutter_rust_bridge.yaml` を使用してバインディングを再生成してください。

### 検証とローカルインストール

```bash
# Dart フォーマット、静的解析、およびテスト
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Rust フォーマット、Lint、およびテスト
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Linux デバッグビルドとネイティブライフサイクル／スモークテスト
fvm flutter build linux --debug
cmake --build build/linux/x64/debug --target bar_lifecycle_test
build/linux/x64/debug/bundle/bar_lifecycle_test
python test/bar_window_smoke.py  # 実行中の Hyprland セッションが必要

# リリースビルドとローカル XDG ディレクトリへのインストール
fvm flutter build linux --release
python tool/install.py
```

## 📜 ライセンス

本プロジェクトは [PolyForm Noncommercial License 1.0.0](../LICENSE) のもとで公開されています。