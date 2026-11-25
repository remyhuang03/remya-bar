import 'dart:io';

const _googleAppHosts = {
  'calendar.google.com',
  'chat.google.com',
  'docs.google.com',
  'drive.google.com',
  'mail.google.com',
  'meet.google.com',
  'tasks.google.com',
};

Uri? googleBrowserLink(String? value) =>
    value == null ? null : _safeBrowserLink(Uri.tryParse(value));

Uri? _safeBrowserLink(Uri? uri) =>
    uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty
    ? uri
    : null;

Uri? googleAuthUser(Uri? uri, String? email) {
  final link = _safeBrowserLink(uri);
  if (link == null) return null;
  if (email == null ||
      email.isEmpty ||
      link.port != 443 ||
      !_googleAppHosts.contains(link.host)) {
    return link;
  }
  return link.replace(
    queryParameters: {...link.queryParametersAll, 'authuser': email},
  );
}

Future<void> openGoogleBrowser(Uri? uri) async {
  final link = _safeBrowserLink(uri);
  if (link == null) throw StateError('Link unavailable.');
  final result = await Process.run('xdg-open', [link.toString()]);
  if (result.exitCode != 0) throw StateError('Could not open this link.');
}
