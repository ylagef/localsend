import 'dart:async';
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
import 'package:localsend_app/provider/background_notifications_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/util/native/receive_notifications.dart';
import 'package:refena_flutter/refena_flutter.dart';

class _Persistence extends Fake implements PersistenceService {
  bool enabled = false;
  bool failWrite = false;
  @override
  bool isBackgroundNotifications() => enabled;
  @override
  Future<void> setBackgroundNotifications(bool value) async {
    if (failWrite) throw StateError('write failed');
    enabled = value;
  }
}

void main() {
  const channel = MethodChannel('main-delegate-channel');
  final capture = GlobalKey();
  late _Persistence persistence;
  late Future<bool> Function() availability;
  late int trayCalls;
  late int hideCalls;

  setUpAll(() async {
    final file = File('/System/Library/Fonts/SFNS.ttf');
    if (file.existsSync()) {
      final font = FontLoader('PersonalSystemFont')..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await font.load();
    }
  });
  setUp(() {
    persistence = _Persistence();
    availability = () async => true;
    trayCalls = 0;
    hideCalls = 0;
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  Future<void> pumpSetting(WidgetTester tester, {Brightness brightness = Brightness.light}) async {
    final theme = getTheme(ColorMode.system, Colors.blue, brightness, null);
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: RefenaScope(
          overrides: [
            backgroundNotificationsProvider.overrideWithNotifier(
              (_) => BackgroundNotificationsService(
                persistence,
                ensureAvailable: () => availability(),
                hideAlerts: () async {
                  hideCalls++;
                },
                keepRunning: () async {
                  trayCalls++;
                },
              ),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
              platform: TargetPlatform.macOS,
              textTheme: theme.textTheme.apply(fontFamily: 'PersonalSystemFont'),
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(padding: EdgeInsets.all(20), child: BackgroundNotificationsSetting()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('availability grant enables notifications and tray, and disabling preserves tray', (tester) async {
    await pumpSetting(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(persistence.enabled, isTrue);
    expect(trayCalls, 1);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(persistence.enabled, isFalse);
    expect(trayCalls, 1);
    expect(hideCalls, 1);
  });

  testWidgets('availability denial does not change tray or persistence', (tester) async {
    availability = () async => false;
    await pumpSetting(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(persistence.enabled, isFalse);
    expect(trayCalls, 0);
    expect(find.text(t.settingsTab.general.notificationDenied), findsOneWidget);
  });

  testWidgets('pending availability disables repeated toggles and restored state is loaded', (tester) async {
    final response = Completer<bool>();
    availability = () => response.future;
    await pumpSetting(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    response.complete(true);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await pumpSetting(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('availability errors leave the control off and usable', (tester) async {
    availability = () async => throw PlatformException(code: 'FAILED');
    await pumpSetting(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(persistence.enabled, isFalse);
    expect(trayCalls, 0);
    expect(find.text(t.general.error), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });

  testWidgets('enabling custom alerts uses availability handshake without OS permission', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'enableReceiveAlerts');
      return true;
    });
    expect(await ensureReceiveAlertsAvailable(), isTrue);
  });

  testWidgets('native card presentation failure and disabled mode permit ordinary fallback', (tester) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      if (call.method == 'showReceiveNotification') throw PlatformException(code: 'DENIED');
      return null;
    });
    Future<bool> notify(bool enabled) =>
        showReceiveNotification(enabled: enabled, sessionId: 'session', kind: 'pending', title: 'Pixel', body: 'Review');
    expect(await notify(false), isFalse);
    expect(calls, 0);
    expect(await notify(true), isFalse);
    expect(calls, Platform.isMacOS ? 1 : 0);
  });

  testWidgets('native card presentation success returns true only after the native response', (tester) async {
    final response = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'showReceiveNotification');
      expect((call.arguments as Map)['kind'], 'done');
      return response.future;
    });
    final future = showReceiveNotification(enabled: true, sessionId: 'session', kind: 'done', title: 'Received', body: 'History');
    response.complete(true);
    expect(await future, Platform.isMacOS);
  });

  testWidgets('capture notification settings in both themes and widths', (tester) async {
    final output = Platform.environment['LOCALSEND_CAPTURE_DIR'];
    if (output == null) return;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final variant in [(Brightness.light, 900.0), (Brightness.dark, 900.0), (Brightness.light, 400.0), (Brightness.dark, 400.0)]) {
      final (brightness, width) = variant;
      tester.view.physicalSize = Size(width, 280);
      await tester.pumpWidget(const SizedBox());
      await pumpSetting(tester, brightness: brightness);
      final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/notifications-${brightness.name}-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
