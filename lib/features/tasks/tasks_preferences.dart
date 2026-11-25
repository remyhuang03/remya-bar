const tasksClockPreferenceKey = 'tasks-clock';

const tasksClockDefaults = <String, Object>{
  'visible-lists': <String>[],
  'visible-lists-account': '',
  'upcoming-days': 7,
  'working-on-enabled': true,
  'working-on-limit': 3,
  'show-assigned': true,
};

class TasksPreferences {
  const TasksPreferences({
    this.visibleLists = const [],
    this.visibleListsAccount = '',
    this.upcomingDays = 7,
    this.workingOnEnabled = true,
    this.workingOnLimit = 3,
    this.showAssigned = true,
  });

  factory TasksPreferences.fromJson(Map value) => TasksPreferences(
    visibleLists: List<String>.unmodifiable(
      (value['visible-lists'] as List).cast<String>(),
    ),
    visibleListsAccount: value['visible-lists-account'] as String,
    upcomingDays: value['upcoming-days'] as int,
    workingOnEnabled: value['working-on-enabled'] as bool,
    workingOnLimit: value['working-on-limit'] as int,
    showAssigned: value['show-assigned'] as bool,
  );

  final List<String> visibleLists;
  final String visibleListsAccount;
  final int upcomingDays;
  final bool workingOnEnabled;
  final int workingOnLimit;
  final bool showAssigned;

  List<String> visibleListsFor(String? accountId) =>
      accountId == visibleListsAccount ? visibleLists : const [];
}
