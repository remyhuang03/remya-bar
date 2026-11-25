import 'package:flutter/foundation.dart';

enum TasksSyncState {
  disconnected,
  loading,
  ready,
  syncing,
  offline,
  authRequired,
  error,
}

@immutable
class TaskList {
  const TaskList({required this.id, required this.title});

  final String id;
  final String title;
}

@immutable
class GoogleTask {
  const GoogleTask({
    required this.id,
    required this.listId,
    required this.title,
    this.position = '',
    this.sourceLink,
    this.webViewLink,
    this.scheduled,
    this.completed = false,
    this.hidden = false,
    this.deleted = false,
    this.assigned = false,
    this.pending = false,
    this.syncError = false,
    this.completionUndoable = false,
    this.accountId,
  });

  final String id;
  final String listId;
  final String title;
  final String position;
  final String? sourceLink;
  final String? webViewLink;
  final DateTime? scheduled;
  final bool completed;
  final bool hidden;
  final bool deleted;
  final bool assigned;
  final bool pending;
  final bool syncError;
  final bool completionUndoable;
  final String? accountId;

  (String, String) get key => (listId, id);
}

class TasksEditException implements Exception {
  const TasksEditException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Google's timestamp carries a calendar date. Do not convert it to local time.
DateTime? googleScheduledDate(Object? value) {
  if (value is! String || value.length < 10) return null;
  final date = value.substring(0, 10);
  final parsed = DateTime.tryParse('${date}T00:00:00Z');
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != date) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}
