import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/android_receive_mode_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  setUpAll(() async {
    final path = Platform.isMacOS ? '/System/Library/Fonts/SFNS.ttf' : '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
    final font = FontLoader('TestSystemFont')..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    await font.load();
  });
  testWidgets('Android receive setting waits for service confirmation and can be disabled', (tester) async {
    bool enabled = false;
    final capture = GlobalKey();
    Future<void> render(Brightness brightness) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        RefenaScope(
          overrides: [
            androidReceiveModeProvider.overrideWithNotifier(
              (_) => AndroidReceiveMode(
                preferred: () => enabled,
                persist: (value) async => enabled = value,
                start: () async => true,
                stop: () async {},
              ),
            ),
          ],
          child: TranslationProvider(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: getTheme(ColorMode.system, Colors.blue, brightness, null).copyWith(
                platform: TargetPlatform.android,
                textTheme: getTheme(ColorMode.system, Colors.blue, brightness, null).textTheme.apply(fontFamily: 'TestSystemFont'),
              ),
              home: RepaintBoundary(
                key: capture,
                child: const Scaffold(
                  body: Padding(padding: EdgeInsets.all(16), child: AndroidReceiveModeSetting()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 440);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await render(Brightness.light);
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(enabled, true);
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(enabled, false);
    // A const setting must react to locale changes without toggling or remounting.
    await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.esEs));
    await tester.pumpAndSettle();
    expect(find.text('Recibir en segundo plano'), findsOneWidget);
    expect(find.text('Receive in background'), findsNothing);
    await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.en));
    await tester.pumpAndSettle();
    final output = Platform.environment['LOCALSEND_CAPTURE_DIR'];
    if (output != null) {
      await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.esEs));
      for (final brightness in Brightness.values) {
        await render(brightness);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/android-receive-${brightness.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.en));
    }
  });
}
