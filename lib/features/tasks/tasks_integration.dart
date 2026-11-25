import '../settings/bar_settings_controller.dart';
import 'tasks_preferences.dart';
import 'tasks_store.dart';

/// Shares preferences and the Tasks store across all Bar views.
class TasksIntegration {
  TasksIntegration()
    : settings = BarSettingsController(
        keys: const [tasksClockPreferenceKey],
        loadAiProviders: false,
      ),
      store = TasksStore.shared {
    settings.addListener(_applyPreferences);
  }

  static final shared = TasksIntegration();

  final BarSettingsController settings;
  final TasksStore store;
  TasksPreferences _preferences = const TasksPreferences();
  Map? _lastValue;

  TasksPreferences get preferences => _preferences;

  Future<void> start() {
    store.start();
    return settings.start();
  }

  void _applyPreferences() {
    final value = settings.values[tasksClockPreferenceKey] as Map?;
    if (value == null || identical(value, _lastValue)) return;
    _lastValue = value;
    _preferences = TasksPreferences.fromJson(value);
    store.setPreferences(_preferences);
  }

  void dispose() {
    settings.removeListener(_applyPreferences);
    settings.dispose();
    store.dispose();
  }
}
