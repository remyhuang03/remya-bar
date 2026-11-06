import 'dart:io';

import '../system/system_backend.dart';

GpuSnapshot? resourceGpu(SystemSnapshot? snapshot) {
  final gpus = snapshot?.gpus ?? const <GpuSnapshot>[];
  final id = snapshot?.resources?.gpuId;
  return gpus.where((gpu) => gpu.id == id).firstOrNull ??
      gpus.where((gpu) => gpu.utilizationPercent != null).firstOrNull ??
      gpus.firstOrNull;
}

Map<String, Object?> resourcePopupData(SystemSnapshot? snapshot) {
  final details = snapshot?.resources;
  final gpu = resourceGpu(snapshot);
  final network = snapshot?.networkOverview;
  return {
    'cpu': snapshot?.cpuPercent,
    'cores': details?.cpuCores,
    'frequency': details?.cpuFrequencyGhz,
    'cpuTemperature': details?.cpuTemperatureCelsius,
    'cpuHistory': details?.cpuHistory,
    'gpuName': gpu?.name,
    'gpu': gpu?.utilizationPercent,
    'gpuTemperature': gpu?.temperatureCelsius,
    'gpuUsed': gpu?.memoryUsedBytes,
    'gpuTotal': gpu?.memoryTotalBytes,
    'gpuHistory': details?.gpuHistory,
    'memoryUsed': snapshot?.memoryUsedBytes,
    'memoryTotal': snapshot?.memoryTotalBytes,
    'memoryCached': details?.memoryCachedBytes,
    'memoryFree': details?.memoryFreeBytes,
    'swapUsed': snapshot?.swapUsedBytes,
    'swapTotal': snapshot?.swapTotalBytes,
    'networkLabel': details?.networkLabel,
    'download': network?.downloadBytesPerSecond,
    'upload': network?.uploadBytesPerSecond,
    'downloadHistory': details?.downloadHistory,
    'uploadHistory': details?.uploadHistory,
    'downloadToday': details?.networkTodayDownloadBytes,
    'uploadToday': details?.networkTodayUploadBytes,
    'todayPartial': details?.networkTodayPartial,
  };
}

Future<void> openSystemMonitor() async {
  for (final id in const [
    'org.gnome.SystemMonitor',
    'org.kde.plasma-systemmonitor',
    'io.missioncenter.MissionCenter',
    'net.nokyan.Resources',
    'mate-system-monitor',
    'xfce4-taskmanager',
  ]) {
    final result = await Process.run('gtk-launch', [id]);
    if (result.exitCode == 0) return;
  }
  throw StateError('No supported system monitor is installed');
}
