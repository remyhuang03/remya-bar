import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/app.dart';

void main() {
  testWidgets('shows Hello, world! in a 40-pixel Material 3 bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 40);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RemyaBarApp());

    expect(find.text('Hello, world!'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(tester.getSize(find.byType(Scaffold)).height, 40);
    final scaffold = tester.element(find.byType(Scaffold));
    expect(Theme.of(scaffold).useMaterial3, isTrue);
    expect(tester.takeException(), isNull);
  });
}
