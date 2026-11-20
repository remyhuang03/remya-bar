import 'dart:io';

import 'tasks_models.dart';

const _googleTasksUrl = 'https://calendar.google.com/calendar/u/0/r/tasks';

Uri? taskHttpsUrl(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  return uri?.scheme == 'https' && uri!.host.isNotEmpty && uri.userInfo.isEmpty
      ? uri
      : null;
}

Future<void> openTaskLink(String? value) async {
  final uri = taskHttpsUrl(value);
  if (uri != null) {
    try {
      final result = await Process.run('xdg-open', [uri.toString()]);
      if (result.exitCode == 0) return;
    } on ProcessException {
      // The opener may be absent on a minimal desktop.
    }
  }
  throw const TasksEditException('Couldn’t open this link.');
}

Future<void> openGoogleTasks([String? value]) =>
    openTaskLink(taskHttpsUrl(value)?.toString() ?? _googleTasksUrl);
