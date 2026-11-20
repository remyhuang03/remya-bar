import '../settings/bar_settings_controller.dart';
import 'tasks_preferences.dart';
import 'tasks_store.dart';

/// All native Bar views share the same preference watch and Tasks store.
class TasksIntegration {
  TasksIntegration()
    : settings = BarSettingsController(
        keys: const ['tasks'],
        loadAiProviders: false,
      ),
      store = TasksStore.shared;

  static final shared = TasksIntegration();

  final BarSettingsController settings;
  final TasksStore store;

  TasksPreferences get preferences {
    final value = settings.values['tasks'] as Map?;
    return value == null
        ? const TasksPreferences()
        : TasksPreferences.fromJson(value, accountId: store.account?.accountId);
  }

  Future<void> start() {
    store.start();
    return settings.start();
  }

  void dispose() {
    settings.dispose();
    store.dispose();
  }

  Future<void> setDefaultList(
    String id,
    String accountId, {
    String? revision,
  }) async {
    if (store.account?.accountId != accountId) {
      throw StateError('The Google account changed.');
    }
    final value = settings.values['tasks'] as Map?;
    if (value == null || settings.busy('tasks')) {
      throw StateError('Tasks settings are busy. Try again.');
    }
    if (id != '' &&
        id != '@default' &&
        !store.lists.any((list) => list.id == id && !list.pending)) {
      throw StateError('Choose an available list.');
    }
    await settings.write('tasks', {
      ...value,
      'default-list': id,
      'default-list-account': id == '@default' ? '' : accountId,
    }, revision: revision);
    if (settings.error('tasks') case final error?) throw StateError(error);
    if (store.account?.accountId != accountId) {
      throw StateError('The Google account changed.');
    }
  }
}
