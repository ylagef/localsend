import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab_controller.dart';
import 'package:localsend_app/pages/tabs/settings_tab_vm.dart';
import 'package:localsend_app/provider/android_receive_mode_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/tv_provider.dart';
import 'package:localsend_app/provider/version_provider.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/device_info_result.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../mocks.mocks.dart';

class _Server extends Fake implements ServerService {}

class _Isolates extends Fake implements IsolateController {}

class _LocalIp extends Fake implements LocalIpService {}

/// Keep the actual SettingsTab tree and platform guards; replace only its external services.
class _SettingsController extends SettingsTabController {
  _SettingsController()
    : super(
        settingsService: SettingsService(MockPersistenceService()),
        serverNotifier: _Server(),
        isolateController: _Isolates(),
        localIpService: _LocalIp(),
        initialDeviceInfo: DeviceInfoResult(deviceType: DeviceType.mobile, deviceModel: 'Pixel 9 Pro', androidSdkInt: 37),
        supportsDynamicColors: false,
      );

  @override
  get initialAction => null;

  @override
  SettingsTabVm init() => SettingsTabVm(
    advanced: false,
    aliasController: TextEditingController(text: 'Pixel'),
    deviceModelController: TextEditingController(text: 'Pixel 9 Pro'),
    portController: TextEditingController(text: '53317'),
    timeoutController: TextEditingController(text: '500'),
    multicastController: TextEditingController(text: '224.0.0.167'),
    settings: SettingsService(MockPersistenceService()).init(),
    serverState: null,
    deviceInfo: DeviceInfoResult(deviceType: DeviceType.mobile, deviceModel: 'Pixel 9 Pro', androidSdkInt: 37),
    colorModes: ColorMode.values,
    autoStart: false,
    autoStartLaunchHidden: false,
    showInContextMenu: false,
    onChangeTheme: (_, _) {},
    onChangeColorMode: (_, _) {},
    onTapLanguage: (_) {},
    onToggleAutoStart: (_) {},
    onToggleAutoStartLaunchHidden: (_) {},
    onToggleShowInContextMenu: (_) {},
    onTapRestartServer: (_) {},
    onTapStartServer: (_) {},
    onTapStopServer: () {},
    onTapAdvanced: (_) {},
  );
}

void main() {
  setUpAll(() async {
    final icons = File('../support/submodules/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
    final fontPath = Platform.isMacOS ? '/System/Library/Fonts/SFNS.ttf' : '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
    await (FontLoader('SettingsTestFont')..addFont(Future.value(ByteData.sublistView(File(fontPath).readAsBytesSync())))).load();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      testWidgets('full settings screen exposes background receiving only on Android: ${platform.name} ${brightness.name}', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        bool enabled = false;
        await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.esEs));
        await tester.pumpWidget(
          RefenaScope(
            overrides: [
              settingsTabControllerProvider.overrideWithNotifier((_) => _SettingsController()),
              versionProvider.overrideWithFuture((_) async => VersionData(version: '1.18.3', buildNumber: '202610343')),
              tvProvider.overrideWithValue(false),
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
                theme: getTheme(ColorMode.localsend, Colors.blue, brightness, null).copyWith(
                  platform: platform,
                  textTheme: getTheme(ColorMode.localsend, Colors.blue, brightness, null).textTheme.apply(fontFamily: 'SettingsTestFont'),
                ),
                home: RepaintBoundary(
                  key: capture,
                  child: const Scaffold(body: SettingsTab()),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final output = Platform.environment['LOCALSEND_CAPTURE_DIR'];
        Future<void> captureScreen(String suffix) async {
          if (output == null || platform != TargetPlatform.android) return;
          final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File('$output/android-settings-${brightness.name}-$suffix.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await captureScreen(Platform.environment['LOCALSEND_CAPTURE_SUFFIX'] ?? 'after');
        if (platform == TargetPlatform.android) {
          expect(find.byType(AndroidReceiveModeSetting), findsOneWidget);
          expect(find.text(t.settingsTab.general.androidReceiveMode), findsOneWidget);
          expect(find.byType(BackgroundNotificationsSetting), findsNothing);
          final modeSwitch = find.descendant(of: find.byType(AndroidReceiveModeSetting), matching: find.byType(Switch));
          await tester.ensureVisible(modeSwitch);
          await tester.tap(modeSwitch);
          await tester.pumpAndSettle();
          expect(enabled, true);
          expect(tester.widget<Switch>(modeSwitch).value, true);
          await tester.ensureVisible(find.text(t.settingsTab.title));
          await tester.pumpAndSettle();
          await captureScreen('enabled');
        } else {
          expect(find.byType(AndroidReceiveModeSetting), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
        await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.en));
      });
    }
  }
}
