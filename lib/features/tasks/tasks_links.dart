import '../google/google_links.dart';
import 'tasks_models.dart';

final _googleTasksPage = Uri.https('calendar.google.com', '/calendar/r/tasks');

Future<void> openGoogleTasks({String? email}) =>
    openGoogleBrowser(googleAuthUser(_googleTasksPage, email));

Future<void> openGoogleTask(GoogleTask task, {String? email}) =>
    openGoogleBrowser(
      googleAuthUser(googleBrowserLink(task.webViewLink), email),
    );

Future<void> openTaskSource(GoogleTask task, {String? email}) =>
    openGoogleBrowser(
      googleAuthUser(googleBrowserLink(task.sourceLink), email),
    );
