import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:system_date_time_format/system_date_time_format.dart';

import '../mocks.mocks.dart';

ReceiveHistoryEntry entry({FileType type = FileType.image, String? path = '/received.png'}) => ReceiveHistoryEntry(
  id: 'received-image',
  fileName: 'Pixel-photo.png',
  fileType: type,
  path: path,
  savedToGallery: false,
  isMessage: false,
  fileSize: 2048,
  senderAlias: 'Pixel',
  timestamp: DateTime.utc(2026, 10, 31, 12),
);

void main() {
  const channel = MethodChannel('main-delegate-channel');
  final captureKey = GlobalKey();

  setUpAll(() async {
    final icons = File('${Directory.current.path}/../support/submodules/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    final iconLoader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await iconLoader.load();
    await initializeDateFormatting();
    final font = File('/System/Library/Fonts/SFNS.ttf');
    if (font.existsSync()) {
      final loader = FontLoader('PersonalSystemFont');
      loader.addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('system_date_time_format'),
      (call) async => call.method == 'getTimeFormat' ? 'HH:mm' : 'dd/MM/y',
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('system_date_time_format'), null);
  });

  Future<void> pumpHistory(WidgetTester tester, ReceiveHistoryEntry item, {Brightness brightness = Brightness.light}) async {
    final persistence = MockPersistenceService();
    when(persistence.getReceiveHistory()).thenReturn([item]);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: RefenaScope(
          overrides: [persistenceProvider.overrideWithValue(persistence)],
          child: SDTFScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: getTheme(ColorMode.system, Colors.blue, brightness, null).copyWith(
                platform: TargetPlatform.macOS,
                textTheme: getTheme(ColorMode.system, Colors.blue, brightness, null).textTheme.apply(fontFamily: 'PersonalSystemFont'),
              ),
              home: const ReceiveHistoryPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) => widget is PopupMenuButton));
    await tester.pumpAndSettle();
  }

  testWidgets('copies an image loaded from persisted receive history', (tester) async {
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (received) async {
      call = received;
      return null;
    });
    await pumpHistory(tester, entry());
    await tester.tap(find.text(t.receiveHistoryPage.entryActions.copyImage));
    await tester.pumpAndSettle();
    expect(call!.method, 'copyImageToClipboard');
    expect(call!.arguments, '/received.png');
    expect(find.text(t.general.copiedToClipboard), findsOneWidget);
  }, skip: !Platform.isMacOS);

  testWidgets('history reports native failure and preserves the entry', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'IMAGE_COPY_FAILED');
    });
    await pumpHistory(tester, entry());
    await tester.tap(find.text(t.receiveHistoryPage.entryActions.copyImage));
    await tester.pumpAndSettle();
    expect(find.text(t.general.error), findsOneWidget);
    expect(find.text(t.general.copiedToClipboard), findsNothing);
    expect(find.text('Pixel-photo.png'), findsOneWidget);
  }, skip: !Platform.isMacOS);

  testWidgets('non-images and pathless entries do not offer image copying', (tester) async {
    for (final item in [entry(type: FileType.pdf), entry(path: null)]) {
      await pumpHistory(tester, item);
      expect(find.text(t.receiveHistoryPage.entryActions.copyImage), findsNothing);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('capture real history widgets with a synthetic Pixel entry', (tester) async {
    final output = Platform.environment['LOCALSEND_CAPTURE_DIR'];
    if (output == null) return;
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final variant in [(Brightness.light, 900.0), (Brightness.dark, 900.0), (Brightness.light, 400.0), (Brightness.dark, 400.0)]) {
      final (brightness, width) = variant;
      tester.view.physicalSize = Size(width, 620);
      await tester.pumpWidget(const SizedBox());
      await pumpHistory(tester, entry(), brightness: brightness);
      final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/history-${brightness.name}${width == 900 ? '' : '-compact'}.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
    }
  }, skip: !Platform.isMacOS);
}
