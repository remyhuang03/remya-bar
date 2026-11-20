import 'package:flutter/foundation.dart';

enum TasksSyncState {
  disconnected,
  loading,
  ready,
  syncing,
  offline,
  authRequired,
  conflict,
  error,
}

@immutable
class TaskList {
  const TaskList({
    required this.id,
    required this.title,
    this.etag,
    this.accountId,
    this.pending = false,
  });

  final String id;
  final String title;
  final String? etag;
  final String? accountId;
  final bool pending;
}

@immutable
class GoogleTask {
  const GoogleTask({
    required this.id,
    required this.listId,
    required this.title,
    this.notes = '',
    this.position = '',
    this.etag,
    this.parent,
    this.sourceLink,
    this.sourceKind,
    this.webViewLink,
    this.scheduled,
    this.completed = false,
    this.hidden = false,
    this.deleted = false,
    this.assigned = false,
    this.pending = false,
    this.error,
    this.accountId,
  });

  final String id;
  final String listId;
  final String title;
  final String notes;
  final String position;
  final String? etag;
  final String? parent;
  final String? sourceLink;
  final String? sourceKind;
  final String? webViewLink;
  final DateTime? scheduled;
  final bool completed;
  final bool hidden;
  final bool deleted;
  final bool assigned;
  final bool pending;
  final String? error;
  final String? accountId;

  Object get key => (listId, id);
}

@immutable
class TasksConflictField {
  const TasksConflictField(this.name, this.mine, this.google);

  final String name;
  final Object? mine;
  final Object? google;
}

@immutable
class TasksConflict {
  const TasksConflict({
    required this.id,
    required this.title,
    required this.message,
    required this.fields,
    required this.canKeepMine,
    this.task,
  });

  final String id;
  final String title;
  final String message;
  final List<TasksConflictField> fields;
  final bool canKeepMine;
  final GoogleTask? task;
}

@immutable
class TasksIssue {
  const TasksIssue({
    required this.id,
    required this.operation,
    required this.title,
    required this.message,
    required this.ambiguous,
    this.task,
  });

  final String id;
  final String operation;
  final String title;
  final String message;
  final bool ambiguous;
  final GoogleTask? task;
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

String googleScheduledDatePayload(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).toIso8601String();
