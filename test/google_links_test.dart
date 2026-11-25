import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/features/google/google_links.dart';

void main() {
  const email = 'bar+calendar@example.test';

  test('Google app links keep existing parameters and select the connected account', () {
    final event = Uri.parse(
      'https://calendar.google.com/calendar/event?eid=abc&authuser=0&arg=a&arg=b',
    );
    final result = googleAuthUser(event, email)!;
    expect(result.path, event.path);
    expect(result.queryParametersAll, {
      'eid': ['abc'],
      'authuser': [email],
      'arg': ['a', 'b'],
    });
    expect(googleAuthUser(event, null), event);
  });

  test('Meeting links preserve third-party signatures and account privacy', () {
    for (final uri in [
      'https://meet.example.test/join?signature=a%2Fb%2Bc',
      'https://calendar.google.com.example.test/join',
      'https://calendar.google.com:8443/join',
    ]) {
      final meeting = Uri.parse(uri);
      expect(googleAuthUser(meeting, email), meeting);
    }
    expect(
      googleBrowserLink('https://calendar.google.com@evil.test/event'),
      isNull,
    );
    expect(googleBrowserLink('file:///tmp/event'), isNull);
  });
}
