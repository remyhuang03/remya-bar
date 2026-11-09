import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/media/bar_media.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/system/system_backend.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

void main() {
  testWidgets('media title rolls at 20 Hz only while enabled', (tester) async {
    BarPopup.keyboardOpen.value = false;
    addTearDown(() => BarPopup.keyboardOpen.value = false);
    Widget host(bool marquee) => BarPopupScope(
      theme: const RemyaTheme(),
      child: MaterialApp(
        home: Center(
          child: SizedBox(
            width: BarMedia.width,
            height: 40,
            child: BarMedia(
              marquee: marquee,
              players: const [
                MediaPlayerSnapshot(
                  busName: 'test',
                  identity: 'Test',
                  title: 'A long media title that must keep scrolling',
                  artist: '',
                  album: '',
                  artUrl: '',
                  playbackStatus: 'Paused',
                  canControl: false,
                  canGoNext: false,
                  canGoPrevious: false,
                  canPlay: false,
                  canPause: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(host(false));
    expect(find.byType(ShaderMask), findsNothing);
    await tester.pumpWidget(host(true));

    ShaderMask mask() => tester.widget<ShaderMask>(find.byType(ShaderMask));

    final initial = mask();
    await tester.pump(const Duration(milliseconds: 49));
    expect(mask(), same(initial));
    await tester.pump(const Duration(milliseconds: 1));
    expect(mask(), isNot(same(initial)));

    BarPopup.keyboardOpen.value = true;
    await tester.pump();
    final paused = mask();
    await tester.pump(const Duration(milliseconds: 250));
    expect(mask(), same(paused));

    BarPopup.keyboardOpen.value = false;
    await tester.pump();
    final resumed = mask();
    await tester.pump(const Duration(milliseconds: 50));
    expect(mask(), isNot(same(resumed)));

    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ShaderMask), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
