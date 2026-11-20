const tasksSettingId = 'remya-bar.tasks';

class TasksPreferences {
  const TasksPreferences({
    this.defaultList = '@default',
    this.defaultListAccount = '',
    this.visibleLists = const [],
    this.visibleListsAccount = '',
    this.initialView = 'today',
    this.sort = 'manual',
    this.completedExpanded = false,
    this.showAssigned = true,
    this.todayIncludesUnscheduled = false,
    this.sidebar = true,
    this.notifications = false,
    this.previewRows = 3,
    this.automatic = true,
  });

  factory TasksPreferences.fromJson(Map value, {String? accountId}) =>
      TasksPreferences(
        defaultList:
            value['default-list-account'] == '' ||
                value['default-list-account'] == accountId
            ? value['default-list'] as String
            : '@default',
        defaultListAccount: value['default-list-account'] as String,
        visibleLists: value['visible-lists-account'] == accountId
            ? List<String>.unmodifiable(
                (value['visible-lists'] as List).cast<String>(),
              )
            : const [],
        visibleListsAccount: value['visible-lists-account'] as String,
        initialView: value['initial-view'] as String,
        sort: value['sort'] as String,
        completedExpanded: value['completed-expanded'] as bool,
        showAssigned: value['show-assigned'] as bool,
        todayIncludesUnscheduled: value['today-includes-unscheduled'] as bool,
        sidebar: value['sidebar'] as bool,
        notifications: value['notifications'] as bool,
        previewRows: value['preview-rows'] as int,
        automatic: value['automatic'] as bool,
      );

  final String defaultList;
  final String defaultListAccount;
  final List<String> visibleLists;
  final String visibleListsAccount;
  final String initialView;
  final String sort;
  final bool completedExpanded;
  final bool showAssigned;
  final bool todayIncludesUnscheduled;
  final bool sidebar;
  final bool notifications;
  final int previewRows;
  final bool automatic;
}
