# Remya Bar 性能调查与优化设计

2026-11-08 起于三屏 Hyprland 工作站。代码基线为 `05efda1`，实验工作树为 `perf/bar-profiling`。Flutter 3.47.8，Dart 3.13.7，Hyprland 0.57.0，NVIDIA RTX 5060 Laptop GPU 615.78.08，另有 Intel i915。显示器为 eDP-1（2560×1600、1.60、120 Hz）、DP-1（1920×1080、1.33、60 Hz）、DP-3（3840×2160、1.67、120 Hz）。

## 结论

- 先处理媒体标题跑马灯。用同一个 release 进程、同一个暂停中的合成 MPRIS 播放器，只替换标题长度，重复切换即可重现 CPU 与帧数的升降。11-09 专项对照以保留持续滚动为约束，见文末。
- 内存先处理弹窗驻留。关闭后的弹窗引擎仍存在。应先量化各弹窗的内存和冷开代价，给高频交互留热路径，再考虑共享引擎多视图。
- 保留事件驱动的快速路径。合并的是重复快照、无变化的 UI 通知和后台兜底轮询。前台操作、状态事件、通知超时及键盘按键时序继续独立调度。

## 采样方法

已安装 release 服务在原会话正常运行。先通过 `/proc`、`perf`、`nvidia-smi` 和 D-Bus 方法计数取样。对照版从独立 worktree 构建 release bundle，直接在同一真实 Wayland 会话运行，使用零预留空间的独立 layer namespace。私有 D-Bus 提供同一套 Settings 只读夹具和暂停的 MPRIS 播放器。合成通知和侧栏信号只发送到该总线。测试应用使用临时 XDG 目录。关闭每轮测试进程后，检查它的全部 layer surface 消失且每个输出的预留空间恢复。

CPU 用进程 `/proc/<pid>/stat` 与各光栅线程的 CPU 时间差计算，100% 对应一个逻辑核。表中不含短命子进程和已安装服务。帧数由 `SchedulerBinding.addTimingsCallback` 每五秒汇总，取落在该阶段内的视图窗口中位数。每个标题阶段稳定 7 秒后取样 16 秒。PSS 取窗口终点，已共享映射按比例计入。NVIDIA 显存单列。各阶段按表内顺序在同一进程切换，Skia 和输出数对照用新进程。两组仅用 DP-3 视图的单屏试验都保留另外两块实体显示器和原服务。NVIDIA 组从测试进程设备文件及驱动显存计数核对实际渲染 GPU。测试场景会出现额外 layer surface 和合成负载。 [Flutter 帧计时 API](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html) · [Flutter DevTools Memory](https://docs.flutter.dev/tools/devtools/memory)

### 安装版基线

三个主 Bar 可见，媒体暂停。三段 10 秒窗口的 CPU 为 **131–140%**，其中三个主 Bar 的光栅线程合计 **97–101%**。用户态 `perf` 采样包含 NVIDIA EGL、Flutter engine 和 Dart AOT 的热点。进程 PSS 约 **1.1 GiB**，匿名 PSS 约 **850 MiB**，NVIDIA 显存约 **608 MiB**。同一 PID 日志有 14 次 Impeller 启动，线程清单有 14 条对应的光栅线程。其中前三个与三屏启动时间对应，其余 11 个在运行中创建。此快照包含已经使用过的弹窗。

一次 22 秒 D-Bus 观察到安装版向 Settings 发送 **336 个 `Get`**，电源、时钟秒数和 Bar 布局分别为 66 次。另一次 25 秒观察到 **24 个 `nvidia-smi` 子进程**，Bar 已回收子进程 CPU 合计约 3.6%，安装版 Settings 服务本身在同一窗口约 37% CPU。后者是服务总量，归因给 Bar 需要逐方法对照。硬件快照已有约 900 ms 进程级共享缓存，因此 GPU 查询实际约每秒一次。当前资源胶囊配置中 GPU 项关闭，卡片及历史需求仍需单独考虑。 [采样实现](../lib/src/rust/system/src/api.rs#L250) · [设置刷新](../lib/features/system/system_backend.dart#L61)

### 受控 release 对照

| GPU | 渲染器与测试视图 | 标题顺序 | CPU % | 光栅 CPU % | 帧/秒/视图 | PSS MiB | NVIDIA 显存 MiB |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| NVIDIA | Impeller 三屏 | 短 → 长 → 短 | 13.1 → 135.8 → 12.2 | 3.5 → 103.1 → 2.9 | 3.3 → 22.2 → 3.4 | 359.9 → 370.8 → 367.5 | 105 → 107 → 105 |
| NVIDIA | Skia 三屏 | 长 → 短 → 长 | 98.4 → 12.5 → 96.5 | 40.4 → 2.2 → 38.3 | 53.5 → 3.9 → 59.9 | 362.3 → 355.9 → 347.3 | 105 → 103 → 105 |
| NVIDIA | Impeller 仅 DP-3 | 短 → 长 | 4.8 → 38.4 | 1.0 → 15.9 | 3.5 → 61.0 | 238.1 → 236.7 | 52 → 53 |
| Intel | Impeller 三屏 | 短 → 长 → 短 | 14.4 → 92.0 → 13.6 | 2.4 → 30.0 → 2.1 | 3.8 → 59.6 → 4.1 | 254.7 → 271.1 → 272.9 | — |
| Intel | Skia 三屏 | 长 → 短 → 长 | 93.3 → 11.9 → 84.4 | 35.8 → 2.4 → 32.7 | 59.2 → 3.8 → 59.5 | 175.2 → 175.7 → 172.7 | — |
| Intel | Impeller 仅 DP-3 | 短 → 长 | 4.8 → 31.8 | 0.7 → 10.6 | 3.7 → 60.9 | 107.2 → 113.4 | — |

NVIDIA Impeller 三屏组切回短标题后，CPU 从 135.8% 回到 12.2%，每视图的帧数从约 22 回到约 3.4。Intel Impeller 三屏组也回到约 14% 和 4 帧/秒。Skia 两组都保留了明显的长标题开销。NVIDIA 长标题时两种渲染器的帧吞吐不同，且原安装服务同时渲染。这组结果支持优先削减无交互帧，也提示 NVIDIA EGL 路径需要独立追踪，单次对照不足以决定更换默认渲染器。

对照验证的是标题溢出会维持每屏的持续帧流。空闲期仍有时钟、资源和 IPC 引起的帧。长标题超过 204 像素媒体胶囊上限，`_ScrollingTitle` 持续调度 ticker 并在绘制路径上使用 `ShaderMask`。其成本随视图数增长。进一步优化遮罩或隔离重绘时应先用 Timeline 确定具体绘制代价。单屏结果用于观察视图数变化，输出组合和 GPU 负载会限制外推。 [标题实现](../lib/features/media/bar_media.dart#L168) · [Flutter 性能最佳实践](https://docs.flutter.dev/perf/best-practices)

### 弹窗内存与响应

| NVIDIA Impeller 三屏 | 首次内容帧 | 热开内容帧中位数 | 关闭后 PSS 中位数 | 关闭后显存中位数 | 引擎数 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 主 Bar 稳态 | — | — | 367.5 MiB | 105 MiB | 3 |
| 通知浮窗关闭后 | 1057.8 ms | 39.0 ms | 407.1 MiB | 123 MiB | 4 |
| 再打开并关闭侧栏后 | 1071.8 ms | 72.6 ms | 462.4 MiB | 159 MiB | 5 |

每类做 1 次冷开和 6 次热开。计时起点是发送合成通知或侧栏快捷信号之前，终点是处理新内容后首个 Flutter post-frame 回调。该指标包含进程间调用和首帧 UI 工作，屏幕实际呈现可能更晚。内存取每次 surface 消失后约 0.6 秒。先测通知，再测侧栏，因此侧栏行包含此前仍驻留的通知引擎。

通知浮窗冷开约 1.06 秒，侧栏冷开约 1.07 秒，热开分别约 39 和 73 ms。两个引擎驻留后，PSS 中位数相对主 Bar 增约 95 MiB，显存增约 54 MiB。热路径与冷开差距意味着直接在每次关闭时销毁通知或侧栏引擎，会给下一次打开带来可感知的代价。Intel 组也观察到通知关闭后仍有第 4 个引擎，PSS 从约 273 MiB 到约 302 MiB。

主窗口及弹窗分别调用 `fl_view_new`，当前 Linux embedding 为该调用创建新引擎。弹窗 `hide()` 隐藏 GTK surface，窗口销毁才释放持有的 `FlView`。这与可见弹窗关闭后线程数仍高一档的观察一致。进程级 PSS 还包含分配器、共享库、图片、纹理与驱动映射，单个弹窗增量受缓存和采样时点影响。安装版十余个隐藏弹窗的总内存不能用单类弹窗增量直接相乘。 [主窗口](../linux/runner/my_application.cc#L48) · [弹窗隐藏](../linux/runner/bar_popup.cc#L95) · [弹窗创建](../linux/runner/bar_popup.cc#L481)

## 优化顺序

### 1. 保留持续滚动，减少每帧工作

- 标题溢出时保持原有持续循环、方向、速度、渐变和完整标题的无障碍标签。保留现有减少动态效果和虚拟键盘策略。专项对照分别量化局部重绘、离屏渐变和只限制跑马灯帧率的收益。
- 播放/暂停、切歌、拖动进度及 MPRIS 更新保留现有即时路径。动画只读取已发布的状态，播放进度仍跟随播放速率和 Seeked 信号。优先缩小动画的 widget 更新范围，必要时根据 Timeline 的 paint 与离屏图层数据试验固定遮罩或局部 `RepaintBoundary`，并检查图层缓存的内存代价。
- 保持 Impeller 为默认候选。Skia 对照用于区分驱动和渲染器成本，评估默认切换时需覆盖弹窗文字、透明合成、比例、动画和首次打开延迟。Flutter 已说明 Linux 将来会移除关闭 Impeller 的入口。 [Flutter 性能最佳实践](https://docs.flutter.dev/perf/best-practices) · [RepaintBoundary](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html) · [MPRIS 播放器接口](https://specifications.freedesktop.org/mpris/latest/Player_Interface.html) · [Impeller Linux](https://docs.flutter.dev/perf/impeller#linux)

### 2. 限制隐藏弹窗的资源

- 先验证隐藏后卸载大图、图表与非可见动画，同时让通知、常用工具提示和侧栏维持有限热路径。低频弹窗只在回收后的首帧也通过门槛时，才进入空闲释放。重新打开应取消待回收操作。通知和侧栏的实测冷开超过一秒，优先验证共享热引擎或受控预热再缩减其引擎数量。预热仅在主 Bar 就绪后的空闲时段执行，并单独计入冷启动和常驻内存。
- 保留并发组合及关闭语义。验证侧栏与虚拟键盘共存、通知浮窗和卡片相互抑制、托盘菜单子菜单及外点关闭、Esc、焦点回归、动画中再开、显示器拔插及无显示器状态。持久的状态由拥有它的后端或窗口控制器保存。
- 只有在每个主 Bar 的独立引擎仍占主要内存，或弹窗冷开无法同时达标时，才试 `fl_view_new_for_engine`。保留每输出的原生 GTK layer-shell、视图 ID 和 40 px 预留。先验证多视图输入、透明渲染、插件注册、输出身份及零尺寸 surface 错误的回归。 [Flutter 多视图 API](https://api.flutter.dev/flutter/widgets/ViewCollection-class.html) · [Flutter View 列表](https://api.flutter.dev/flutter/dart-ui/PlatformDispatcher/views.html)

### 3. 合并后台读取并隔离即时事件

| 路径 | 拟议变化 | 必须保留的快速路径 |
| --- | --- | --- |
| Hyprland 工作区、窗口与全屏 | 复用同一批 monitors/clients/workspaces 的进程级快照，按受影响输出发布差异。重连、溢出和事件缺失仍可强制补齐 | 点击、滚轮和全屏切换即时发出命令或触发局部刷新。动作执行与后台快照重试独立，保留现有的事件合并上限和 Super 反馈 |
| Settings 偏好、音量与连接状态 | 静态偏好启动、`Changed`、重连时读一次。外部状态采用已有信号和按需首读，保留低频兜底。不同输出读取同一份带版本的结果 | 侧栏打开立即显示最近有效数据，并开始当前输出的刷新。开关、滑块和媒体音量仍走现有即时写入、回读与版本保护 |
| 托盘 SNI 与 D-Bus 菜单 | 先合并各屏相同的条目和图标查询，再用注册、注销、图标和状态事件更新脏条目。对缺失信号的实现保留兼容轮询 | 菜单打开仍取最新布局，子菜单、滚轮和点击直接派发。关注态和图标更新不能被慢轮询拖住 |
| 资源与电池 | 把 NVIDIA 子进程从通用采样周期中拆开，根据配置和打开卡片的需求调度。保留历史时间轴、真实缺失值和 CPU/网络差分基线 | 打开卡片即时呈现最近样本并触发异步刷新。电源切换和插拔状态走高优先级事件，避免被 GPU 查询阻塞 |
| 通知和虚拟键盘 | 让空闲回收、图像缓存和资源采样独立于通知和键盘处理 | 保留通知过期、悬停暂停、动作和 DND 语义。按键 down/up、修饰键、长按连发、目标焦点和音量拖动沿原有低延迟路径 |

按变化范围更新胶囊。现有 `Listenable.merge` 把系统、Hyprland、通知和主题放在整个 `MaterialApp` 的重建入口，资源样本每秒发通知。先测稳定页面的 build/layout/paint，再让各组件订阅它们需要的字段。采用先订阅再读取、快照版本检查和事件丢失重同步，避免读回覆盖新值。 [Bar 重建入口](../lib/app.dart#L549) · [Hyprland 事件](../lib/features/hyprland/hyprland_backend.dart#L111) · [托盘轮询](../lib/features/tray/bar_tray.dart#L44) · [Settings D-Bus 公共 API](../../remya-settings/docs/public-api.md) · [StatusNotifierItem 事件规范](https://specifications.freedesktop.org/status-notifier-item/latest-single/)

## 实施时的验收

- 固定版本、相同显示拓扑、GPU 与驱动。无媒体、短标题、长标题暂停/播放分别做至少三段 60 秒的 release 采样。记录 Bar CPU、光栅 CPU、每屏帧数、PSS、显存、线程及引擎数。单独记录 Settings 进程与子进程，不混进主进程数据。
- 对时间敏感路径分别测冷、热和同时发生后台刷新时的响应。用同一机器与输入序列每场景至少 30 次，报告 p50、p95 和最大值。合成 D-Bus 用于受控测量，真实点击、滚轮和键盘另测输入事件至 Wayland presentation feedback 或目标应用接收的时间。Flutter post-frame 和 surface 映射用于定位各段成本。 [Wayland presentation-time 协议](https://wayland.app/protocols/presentation-time)
- 跑马灯优化以同机同屏数、持续滚动且同等外观的基线对照。若采用跑马灯专属更新频率，额外验证连续性、每圈时长、真实呈现间隔和高 DPI 观感。键盘按键、点击和工作区的 p95 增量至多一帧（60 Hz 约 16.7 ms，120 Hz 约 8.3 ms，按实际呈现节奏检查），交互事件零丢失或乱序。通知、侧栏、菜单与悬停卡片分别对比冷开和热开，已有等待时长保持，p95 增量至多一帧。超标则调整预热或延后引擎回收。电源、蓝牙和网络等外部状态还需核对重连和外部变更的收敛延迟。
- 对弹窗循环开关 30 次，检查隐藏窗口的引擎数、PSS 和显存能回到稳定区间，并按交互门槛验证回收后的下一次打开。再用 profile 构建和 DevTools Performance 查看 build、layout、paint、raster 和卡顿时间线。用 Memory 的 heap/external/raster-cache 曲线及快照定位占用来源，最终收益以 release 及系统级采样为准。 [Flutter Performance](https://docs.flutter.dev/tools/devtools/performance) · [Flutter Memory](https://docs.flutter.dev/tools/devtools/memory)

## 复现与恢复

在 perf 工作树执行 `fvm flutter build linux --release`。驱动脚本、私有总线配置和夹具位于 [build/profiling](../build/profiling)。测试 bundle 的窗口标记、输出筛选、渲染器切换和帧打点由实验环境变量开启。脚本先校验私有总线与原会话地址不同，然后依次运行 Impeller 三视图、Skia 三视图与 Impeller 单视图，在退出路径终止测试子进程并检查 surface。合成通知在私有总线内过期，不进入原通知中心。

```bash
export BAR_PERF_HOST_BUS="$DBUS_SESSION_BUS_ADDRESS" BAR_PERF_MONITOR_X=0
export BAR_PERF_DRIVER_TAG=nvidia __GLX_VENDOR_LIBRARY_NAME=nvidia __NV_PRIME_RENDER_OFFLOAD=1
unset __EGL_VENDOR_LIBRARY_FILENAMES
dbus-run-session --config-file=build/profiling/private-session.conf -- python build/profiling/run.py
```

原始记录包括 [Intel 组](../build/profiling/results.json)、[NVIDIA 组](../build/profiling/results-nvidia.json) 和同目录的逐引擎五秒帧日志。重新运行会覆盖对应标签的日志和 JSON，可用不同的 `BAR_PERF_DRIVER_TAG` 保留独立记录。现有计时覆盖通知和侧栏的受控首帧路径。托盘、悬停卡片、虚拟键盘、工作区真实输入、实际呈现时间、热插拔和不同机器留给实施验收。

实验结束后，只有原安装 Bar 进程存活，通知总线名称仍由它持有。服务保持 active/enabled，PID 与原启动时间一致，无临时 drop-in。对照前后安装目录的可执行文件、Dart AOT 和 Flutter engine 校验一致。三个输出各保留一个 40 px 主 Bar，预留空间仍为 `[0,40,0,0]`，无测试 layer surface。Bar 与 Settings 的 main 工作树干净。本次代码变更限于本地 perf 工作树的测量入口，优化停留在设计阶段。

## 2026-11-09 跑马灯专项

本轮只比较长标题持续循环时的不同成本。媒体一直暂停，展示相同标题和两段之间的 32 逻辑像素间隔，滚动速度为 16 逻辑像素/秒。主 Bar 继续运行在实机，测试实例用原报告的私有 D-Bus、测试 namespace 和零额外预留空间。实测拓扑为 eDP-1 与 DP-3 两屏，均为约 120 Hz，且 GTK 使用 2 倍 buffer scale。此前的三屏结果属于不同拓扑。各 GPU 使用一个 release 进程，切换合成标题前缀选择实验项，前缀不参与绘制。每项稳定 7 秒，取样 16 秒，原实现各测开头和末尾。各版保持原工作区、托盘、通知和 Settings 测试场景。这里的帧率由 Flutter engine 报告。

### 逐项对照

| 跑马灯仍在持续运行的版本 | NVIDIA CPU % | NVIDIA 帧/秒/视图 | Intel CPU % | Intel 帧/秒/视图 |
| --- | ---: | ---: | ---: | ---: |
| 原实现，两端对照 | 75.3 / 83.7 | 60.4 / 60.1 | 70.8 / 65.4 | 59.7 / 60.2 |
| 仅给静态文字条加重绘边界 | 78.4 | 60.7 | 65.1 | 60.3 |
| 仅缓存两种渐变 Shader | 82.0 | 60.6 | 67.9 | 60.1 |
| 硬裁切，暂去边缘渐变 | 75.0 | 60.7 | 63.6 | 60.3 |
| Flow 绘制位移，保留渐变 | 68.6 | 59.8 | 53.4 | 60.2 |
| 仅跑马灯 30 Hz，保留渐变 | 45.8 | 32.3 | 41.5 | 31.7 |

- **Flow 保持约 60 帧/秒。** 与本轮两端基线均值相比，NVIDIA 和 Intel 的进程 CPU 分别下降约 14% 和 22%。5 秒区间 build p95 的中位数约从 1.3 到 1.0 ms、从 1.5 到 0.9 ms。NVIDIA 区间 raster p95 中位数同时从两端基线的 4.0/6.4 ms 升到 10.4 ms。NVIDIA 交替复测中，原实现 → Flow 的 CPU 为 74.5% → 61.2% 和 78.0% → 68.6%。第一对保持约 60 帧/秒，第二对 Flow 降至约 54 帧/秒。两对 raster p95 中位数分别从 3.7 到 4.2 ms 和从 4.6 到 6.5 ms。总 CPU 降低能复现，原呈现节奏和慢帧指标尚未通过。
- **单独把跑马灯调度降到 30 Hz**，整个视图仍因其他更新达到约 32 帧/秒。两组 CPU 分别降约 42% 和 39%。动画仍按原速循环，细微呈现节奏发生变化。
- **仅缓存 Shader、加重绘边界或移除遮罩的收益较小。** 前两项大多落在两端基线的波动范围。去掉渐变的对照仍接近每秒 60 帧，NVIDIA 约 75% CPU，Intel 约 64%。保留渐变更符合原组件外观。

原实现已经把两个文字副本放进 `AnimatedBuilder.child`，动画 tick 不会每次重建文字组件。tick 会重建外部的裁切、遮罩和位移 widget，并提交新 scene。渐变只有两种左边缘状态，复用 Shader 仅减少构造。Flutter 3.47.8 的 `ShaderMaskLayer` 仍需用 `saveLayer` 混合或使用缓存结果。持续移动使得局部缓存无法消除每帧 scene 提交。 [AnimatedBuilder](https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html) · [Flutter 性能最佳实践](https://docs.flutter.dev/perf/best-practices#use-savelayer-thoughtfully) · [ShaderMaskLayer 源码](/home/remy/fvm/versions/3.47.8/engine/src/flutter/flow/layers/shader_mask_layer.cc:50)

`FlowDelegate(repaint: phase)` 只更新文字条绘制位置，遮罩在左侧渐变状态改变时才重新配置。原型复用 Shader，也有 `RenderFlow` 自身的重绘边界。它是保持视觉与刷新节奏的候选。不能把它的总变化只归因给一个组件。文字层没有独立的鼠标操作，完整胶囊仍负责点击和语义。 [Flow](https://api.flutter.dev/flutter/widgets/Flow-class.html) · [RepaintBoundary](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html)

### 原生 GTK 提交成本

用进程内符号探针包住 `gdk_cairo_draw_from_gl`，按尺寸每五秒累加 GTK 调用次数和线程 CPU 时间。两屏传入的都是整条 Bar 的 **3200×80** 和 **4608×80** buffer，标题视口的裁切没有改变 GTK 调用范围。

| NVIDIA 原生探针 | 两屏合计 GTK 调用/秒 | GTK 单函数 CPU | 整个 Bar CPU |
| --- | ---: | ---: | ---: |
| 静态短标题，作为对照 | 约 7 | 约 0.7% | 9.4% |
| 原实现持续滚动，两端对照 | 约 116–118 | 约 9.5–10.1% | 74.8–82.1% |
| 去遮罩，持续滚动 | 约 119 | 约 10.2% | 71.3% |
| 30 Hz 跑马灯 | 约 62 | 约 5.9% | 46.6% |

这是一个原生函数在所选稳定窗口的 CPU 时间，光栅线程合成和 GTK 其他工作另外计入进程。即使只改变几个字形，也会持续产生整窗提交。去遮罩后的 GTK 次数和函数 CPU 基本相同，保留这项视觉效果仍有较大的平台层优化空间。

当前 Linux embedding 在 Wayland 走 EGLImage 共享路径。在 Flutter 光栅线程合成各层以后，GTK 线程仍将完整尺寸传给 `gdk_cairo_draw_from_gl`。这个调用包括平台层和驱动工作。源码中 Flutter 自身的显式 `glReadPixels` 分支由非共享路径触发，当前 Wayland 测试不应直接套用；GTK 是否在内部回读另需独立追踪。 [Flutter 3.47.8 Wayland renderer](/home/remy/fvm/versions/3.47.8/engine/src/flutter/shell/platform/linux/fl_view_renderer.cc:99) · [OpenGL compositor](/home/remy/fvm/versions/3.47.8/engine/src/flutter/shell/platform/linux/fl_compositor_opengl.cc:272)

Flutter 的 Linux 高 CPU issue 也用持续动画的进度指示器复现过。上游尚未合入的 PR #195287 针对较新的 Wayland subsurface renderer 取消每帧父 GTK 重绘，作者的 GNOME/Mesa release 对照里，持续进度动画的 app CPU 从 master 的 16.4% 到补丁版 3.2%。这是独立应用和不同合成器的结果，Remya Bar 的收益需要在锁定 SDK 上另跑。Linux 帧调度和实际呈现的差异仍有专门 issue。常用的 `marquee` 包源码同样通过 ScrollController 反复驱动动画，换包本身没有证据能消除 GTK 提交。 [Flutter #101591](https://github.com/flutter/flutter/issues/101591) · [Wayland subsurface PR #195287](https://github.com/flutter/flutter/pull/195287) · [帧调度 #191245](https://github.com/flutter/flutter/issues/191245) · [marquee 源码](https://github.com/MarcelGarus/marquee/blob/master/lib/marquee.dart)

### 保持持续滚动的方案

1. **若允许改变更新频率，先验证跑马灯专属 30 Hz。** 用单调时钟计算位置，仍按 16 逻辑像素/秒无间歇循环，渐变、间隔、方向及现有暂停策略保持。在 30 Hz 时每次位移约 0.53 逻辑像素，2× buffer 约 1.07 像素。应实看 60/120 Hz 和分数缩放，确认连续性和抖动。由跑马灯自己按需请求帧。时钟、通知、点击、键盘、工作区和媒体动作的调度继续独立。一直运行 60 Hz ticker 而只跳过部分 widget 更新，ticker 仍会请求框架帧，不能等同于本次对照。 [TickerMode](https://api.flutter.dev/flutter/widgets/TickerMode-class.html) · [Flutter ticker 源码](/home/remy/fvm/versions/3.47.8/packages/flutter/lib/src/scheduler/ticker.dart:272)
2. **若约 60 Hz 观感也是硬约束，先复核 paint-only，再验证平台路径。** 采用 `Flow` 或等价 paint-only 方式前，先处理 NVIDIA 复测中的 raster 尾延迟，再判断是否值得采用。widget 测试已比对 LTR 与 RTL 布局的 5 个相位，2× 输出逐像素一致，包含滚动和循环接缝附近；后续仍需实测中英与实际 RTL 文字、字号、主题和播放状态，并在相同帧率下复测 CPU。GTK 的 Wayland subsurface 路径值得单独 A/B，需保留透明度、每屏 layer-shell、40 px 预留、热插拔、弹窗首帧和焦点规则。该方向等有适合测试的 SDK 或 engine artifact 后验证，当前 Flutter 固定版本继续使用。
3. **用真实呈现和输入确认结果。** 框架帧数用于定位，`wp_presentation` 用于核对实际显示间隔。每个配置至少做三段 60 秒，取同拓扑 CPU、各线程时间和呈现间隔。通过中英及 RTL 标题、短标题、播放暂停、切歌、键盘开启与关闭、减少动态效果以及无悬停长时间循环。工作区切换、媒体点击、通知和虚拟键盘的 p95 响应延迟沿用原报告门槛。 [Flutter Performance view](https://docs.flutter.dev/tools/devtools/performance) · [Wayland presentation-time](https://wayland.app/protocols/presentation-time)

### 复现和证据

在 perf 工作树以 `fvm flutter build linux --release` 构建。沿用上述独立总线启动命令，入口换为 `build/profiling/marquee.py`，两组分别设置 `BAR_PERF_DRIVER_TAG=marquee-nvidia` 和 `marquee-intel`。Intel 使用 Mesa EGL vendor、`__NV_PRIME_RENDER_OFFLOAD=0`。用 `--repeat-flow` 交替复测，换用独立标签 `marquee-repeat-nvidia`。原生探针用下列命令构建，再以 `--gtk` 和标签 `marquee-gtk-nvidia` 启动脚本。

```bash
cc -shared -fPIC -Wall -Wextra -O2 $(pkg-config --cflags gdk-3.0) \
  build/profiling/gtk_draw_probe.c -o build/profiling/gtk_draw_probe.so -ldl
REMYA_BAR_PERF=1 fvm flutter test build/profiling/marquee_visual_test.dart
```

[双屏 NVIDIA 数据](../build/profiling/results-marquee-nvidia.json) · [双屏 Intel 数据](../build/profiling/results-marquee-intel.json) · [Flow 交替复测](../build/profiling/results-marquee-repeat-nvidia.json) · [GTK 探针数据](../build/profiling/results-marquee-gtk-nvidia.json) · [GTK 原生日志](../build/profiling/marquee-gtk-nvidia-continuous.log) · [像素对照日志](../build/profiling/marquee-visual.log)

本次的试验入口和候选实现留在本地 perf 工作树。指标用于筛选方案。实机 Wayland 呈现节奏、长时稳定性与输入延迟留待正式实施验收。

复查通过 release 构建、Flutter 静态分析、原有 77 项测试与两项像素对照。所有测试实例和 layer surface 已撤下，原安装文件校验一致，原服务保持同一 PID 且拥有通知总线名称。两个测试时已启用的输出各保留原 Bar 的 40 px 预留空间。
