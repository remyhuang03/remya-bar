<p align="center">
  <img src="../assets/icons/app_icon-full.svg" width="128" alt="Icono de Remy'a Bar">
</p>

<h1 align="center">Remy'a Bar</h1>

<h3 align="center">Barra de estado multifunción para Arch Linux Hyprland</h3>

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
  <strong>Español</strong> ·
  <a href="README.ja.md">日本語</a>
</p>

Una barra de estado de escritorio moderna y fluida para **Linux Hyprland**, creada con **Flutter** y **Material Design 3 Expressive**, e impulsada por un motor **Rust** de alto rendimiento. Inspirada visualmente en [illogical-impulse's Bar](https://github.com/end-4/dots-hyprland/tree/main/dots/.config/quickshell/ii/modules/ii/bar), ofrece un completo conjunto de widgets de estado.

> [!WARNING]
> Este software se encuentra actualmente en fase **Beta** y puede presentar errores o inestabilidad. Sus funciones y comportamiento siguen perfeccionándose, y la optimización de rendimiento continúa en curso.

<p align="center">
  <video src="images/hero-demo.mp4" controls autoplay loop muted playsinline width="100%"></video>
</p>

## 🚀 Instalación

`remya-bar` depende del servicio D-Bus `top.remya.Core1` proporcionado por **Remya Core** (`remya-core` / `remyad`) para gestionar los tokens de tema compartidos y la persistencia de la configuración. Instala y habilita primero **Remya Core** antes de instalar **Remy'a Bar** (`top.remya.bar.service` se ordena automáticamente para iniciarse después de `top.remya.core.service`; **Remya Settings** es un frontend opcional de ajustes del sistema).

### 1a. Instalar mediante AUR (Recomendado)

Instala `remya-bar` con tu asistente de AUR preferido:

```bash
paru -S remya-bar || yay -S remya-bar
```

### 1b. Instalar desde el archivo de lanzamiento (Linux x86_64)

Tras descargar el archivo de lanzamiento para Linux x86_64 desde [Releases](https://github.com/remyhuang03/remya-bar/releases), puedes instalarlo usando el script incluido `tool/install.py`:

```bash
# Verificar la suma de comprobación
sha256sum -c SHA256SUMS --ignore-missing

# Extraer e instalar
tar --zstd -xf remya_bar-<version>-linux-x86_64.tar.zst
cd remya_bar-<version>-linux-x86_64
python tool/install.py
```

El instalador copia los archivos en `~/.local/bin` y `XDG_DATA_HOME`, crea y habilita la unidad de usuario systemd `top.remya.bar.service` y configura la barra para iniciarse junto con `graphical-session.target` (requiere `WAYLAND_DISPLAY` y `HYPRLAND_INSTANCE_SIGNATURE` en el entorno del gestor de usuario, por ejemplo proporcionados por `uwsm`). Al reinstalar, detiene automáticamente la unidad, reemplaza el paquete y reinicia el servicio. Ejecuta `systemctl --user disable --now top.remya.bar.service` para desactivar el inicio automático.

### 2. Configuración de Hyprland

Añade los siguientes atajos de teclado en tu configuración Lua de Hyprland (por ejemplo, `~/.config/hypr/hyprland.lua`) (si ya tenías atajos previos, puedes eliminarlos primero con `hl.unbind(...)`):

```lua
local barShortcutSignal = 'gdbus emit --session --object-path /top/remya/bar --signal top.remya.bar.Shortcuts.'

-- Alternar la barra lateral de Ajustes rápidos
hl.bind(
    "SUPER + A",
    hl.dsp.exec_cmd(barShortcutSignal .. 'ToggleSidebar "$HYPRLAND_INSTANCE_SIGNATURE"')
)

-- Atajos de volumen y brillo
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

## ✨ Características

### Cápsulas de la barra de estado

<table>
  <tr>
    <th>Cápsula</th>
    <th>Descripción</th>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-sidebar.svg" alt="Cápsula de Ajustes rápidos" height="34"></td>
    <td><strong>Acceso rápido</strong>: integra el estado de red, Bluetooth, volumen y más; haz clic para abrir el centro de control.</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-media.svg" alt="Cápsula de control multimedia" height="34"></td>
    <td><strong>Reproducción multimedia</strong>: muestra la pista actual y permite pausar/reanudar o cambiar de canción con un clic.</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-clock.svg" alt="Cápsula de reloj" height="34"></td>
    <td><strong>Reloj y fecha</strong>: muestra con precisión la hora y fecha actuales; haz clic o pasa el cursor para abrir el calendario.</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-workspaces.svg" alt="Cápsula de espacios de trabajo" height="34"></td>
    <td><strong>Espacios de trabajo</strong>: muestra los iconos de aplicaciones, ventanas enfocadas y avisos urgentes en cada espacio.</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-resources.svg" alt="Cápsula de recursos del sistema" height="34"></td>
    <td><strong>Recursos del sistema</strong>: muestra en tiempo real el uso de CPU, memoria y otros recursos.</td>
  </tr>
  <tr>
    <td align="center"><img src="images/pill-ai-quota.svg" alt="Cápsula de cuota de IA" height="34"></td>
    <td><strong>Uso de IA</strong>: muestra de forma clara la cuota restante y la hora de restablecimiento de tus suscripciones de IA.</td>
  </tr>
</table>

### Paneles flotantes y centro de control

<table>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-resources.svg" alt="Panel de monitorización de recursos" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-datetime.svg" alt="Panel de fecha y hora" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>Monitor del sistema</b>: CPU, GPU, asignación de memoria y gráficas de red de 60 segundos</sub></td>
    <td align="center"><sub><b>Fecha y hora</b>: reloj grande, hora mundial, número de semana y calendario mensual interactivo</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-media.svg" alt="Panel de control multimedia" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-battery.svg" alt="Panel de batería y modo de energía" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>Control multimedia</b>: colores adaptativos según la carátula, barra de progreso y volumen</sub></td>
    <td align="center"><sub><b>Batería y energía</b>: nivel, consumo, salud, ciclos de carga y cambio de perfil de rendimiento</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-card-ai-quota.svg" alt="Panel de estadísticas de uso de IA" width="100%">
    </td>
    <td width="50%" align="center" valign="top">
      <img src="images/demo-sidebar.svg" alt="Centro de control de Ajustes rápidos" width="97%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub><b>Uso de IA</b>: cuotas de sesión y semanales multiplataforma, cuenta atrás y consumo diario</sub></td>
    <td align="center"><sub><b>Ajustes rápidos</b>: interruptores rápidos del sistema y accesos directos a utilidades</sub></td>
  </tr>
</table>

### Indicadores en pantalla (OSD)

<table>
  <tr>
    <td width="45%" align="center">
      <img src="images/demo-osd.svg" alt="Indicador en pantalla OSD" width="280">
    </td>
    <td>
      <ul>
        <li><strong>Volumen y amplificación</strong>: al ajustar el volumen o activar el refuerzo por encima del límite, aparece una cápsula de progreso centrada en la parte superior.</li>
        <li><strong>Brillo y atenuación por software</strong>: admite avisos de retroiluminación por hardware y brillo por software, diferenciando claramente el modo activo.</li>
        <li><strong>Notificaciones y No molestar</strong>: registra de forma centralizada las notificaciones perdidas, con borrado en un clic e interruptor de No molestar.</li>
      </ul>
    </td>
  </tr>
</table>

## ⌨️ Desarrollo

### Stack tecnológico y arquitectura

- **Flutter**: fijado en `3.47.9` mediante FVM, junto con Material Design 3 Expressive (`material_ui`).
- **Rust**: edición `2024`, gestionado como un workspace de Cargo con el archivo `rust-toolchain.toml` en la raíz.
- **FFI**: conecta `remya_bar_hyprland` y `remya_bar_system` con Flutter mediante `flutter_rust_bridge`.
- **Wayland**: runtime nativo GTK enlazado dinámicamente con `gtk-layer-shell` para ventanas de barra por monitor, el host flotante `BarPopup` y la ventana independiente `--settings`.
- **Integración con Core**: se conecta a `remya-core` mediante D-Bus de sesión (`top.remya.Core1`) a través de los paquetes `remya_client` y `remya_ui` para gestionar temas compartidos y persistencia atómica de preferencias. Consulta [docs/backend.md](backend.md) para ver los detalles del contrato.

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

- **Estructura de directorios**:
  - `lib/main.dart` y `lib/app.dart`: arranque de la aplicación y composición del widget raíz.
  - `lib/features/`: interfaz Flutter, estado y controladores organizados por módulos funcionales.
  - `lib/src/rust/`: crates modulares de Rust (`hyprland`, `system`, `core` y crates puente generados).
  - `linux/`: runtime nativo GTK, configuración de `gtk-layer-shell` y scripts de empaquetado de escritorio.
  - `assets/icons/`: icono de la aplicación e iconos de funciones.
  - `tool/install.py`: script auxiliar de instalación XDG y servicio de usuario systemd.

### Requisitos previos y configuración

- FVM con Flutter SDK `3.47.9`
- Toolchain de Rust (edición `2024`) gestionado con `rustup`
- Durante el desarrollo se requiere una copia hermana en `../remya-core` para proporcionar `packages/remya_client` y `packages/remya_ui` (los paquetes compilados de lanzamiento no requieren el código fuente hermano)
- En tiempo de ejecución es necesario tener instalado y habilitado **Remya Core** (que proporciona `dbus-1/services/top.remya.Core1.service` y `top.remya.core.service`)
- Dependencias de ejecución y compilación nativa en Arch Linux:

| Dependencia | Propósito |
| :--- | :--- |
| `gtk-layer-shell`, `wayland`, `libxkbcommon`, `wayland-protocols` | Superficies Wayland layer-shell, entrada y `wayland-scanner` |
| `sqlite` | Historial persistente de notificaciones |
| `inter-font`, `noto-fonts-cjk` | Tipografía del sistema y respaldo para caracteres CJK |
| `networkmanager`, `bluez` | Interruptores de red y Bluetooth en Ajustes rápidos |
| `nvidia-utils` *(opcional)* | Proporciona `libnvidia-ml.so.1` para métricas de GPU NVIDIA |
| `codexbar-cli` *(opcional)* | Proporciona el ejecutable `codexbar` para la cuota de IA |

```bash
fvm install
fvm flutter pub get
```

Tras modificar la API del puente Rust, vuelve a generar los bindings usando `flutter_rust_bridge_codegen` y `flutter_rust_bridge.yaml`.

### Validación e instalación local

```bash
# Formato, análisis estático y pruebas de Dart
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# Formato, lints y pruebas de Rust
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

# Compilación debug en Linux y pruebas nativas de ciclo de vida / humo
fvm flutter build linux --debug
cmake --build build/linux/x64/debug --target bar_lifecycle_test
build/linux/x64/debug/bundle/bar_lifecycle_test
python test/bar_window_smoke.py  # Requiere una sesión activa de Hyprland

# Compilación release e instalación en directorios XDG locales
fvm flutter build linux --release
python tool/install.py
```

## 📜 Licencia

Este proyecto se distribuye bajo la licencia [PolyForm Noncommercial License 1.0.0](../LICENSE).