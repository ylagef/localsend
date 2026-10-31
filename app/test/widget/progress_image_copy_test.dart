import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/model/state/server/receiving_file.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/model/state/settings_state.dart';
import 'package:localsend_app/pages/progress_page.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/widget/copy_image_button.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_status.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';

class _Settings extends Fake implements SettingsState {
  @override
  bool get autoFinish => false;
}

class _Persistence extends Fake implements PersistenceService {}

class _SettingsService extends SettingsService {
  _SettingsService() : super(_Persistence());
  @override
  SettingsState init() => _Settings();
}

class _ServerService extends ServerService {
  final ServerState initial;
  _ServerService(this.initial);
  @override
  ServerState? init() => initial;
}

class _Sender extends Fake implements Device {}

void main() {
  const channel = MethodChannel('main-delegate-channel');
  final captureKey = GlobalKey();

  setUpAll(() async {
    final icons = File('${Directory.current.path}/../support/submodules/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    final iconLoader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await iconLoader.load();
    final file = File('/System/Library/Fonts/SFNS.ttf');
    if (file.existsSync()) {
      final font = FontLoader('PersonalSystemFont')..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await font.load();
    }
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  Future<void> pumpTransfer(
    WidgetTester tester, {
    FileStatus status = FileStatus.finished,
    FileType type = FileType.image,
    Brightness brightness = Brightness.light,
  }) async {
    const sessionId = 'received-session';
    final file = FileDto(id: 'photo', fileName: 'Pixel-photo.png', size: 2048, fileType: type, hash: null, preview: null, metadata: null);
    final session = ReceiveSessionState(
      sessionId: sessionId,
      status: status == FileStatus.finished ? SessionStatus.finished : SessionStatus.sending,
      sender: _Sender(),
      senderAlias: 'Pixel',
      files: {
        'photo': ReceivingFile(
          file: file,
          token: 'token',
          desiredName: file.fileName,
          path: '/received.png',
          savedToGallery: false,
          errorMessage: null,
        ),
      },
      startTime: null,
      endTime: null,
      destinationDirectory: '/Downloads',
      cacheDirectory: '/cache',
      saveToGallery: false,
      createdDirectories: {},
    );
    final transfers = FileTransferNotifier()
      ..setStatus(sessionId: sessionId, fileId: 'photo', status: status)
      ..setProgress(sessionId: sessionId, fileId: 'photo', progress: status == FileStatus.finished ? 1 : 0);
    final theme = getTheme(ColorMode.system, Colors.blue, brightness, null);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: RefenaScope(
          overrides: [
            serverProvider.overrideWithNotifier(
              (_) => _ServerService(ServerState(alias: 'LocalSend Personal', port: 53317, https: true, session: session, web: null)),
            ),
            settingsProvider.overrideWithNotifier((_) => _SettingsService()),
            fileTransferProvider.overrideWithNotifier((_) => transfers),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
              platform: TargetPlatform.macOS,
              textTheme: theme.textTheme.apply(fontFamily: 'PersonalSystemFont'),
            ),
            home: const ProgressPage(showAppBar: true, closeSessionOnClose: true, sessionId: sessionId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('completed received image copies from the transfer page', (tester) async {
    MethodCall? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      copied = call;
      return null;
    });
    await pumpTransfer(tester);
    await tester.tap(find.byType(CopyImageButton));
    await tester.pumpAndSettle();
    expect(copied!.method, 'copyImageToClipboard');
    expect(copied!.arguments, '/received.png');
    expect(find.text(t.general.copiedToClipboard), findsOneWidget);
  }, skip: !Platform.isMacOS);

  testWidgets('unfinished images and received non-images do not offer copying', (tester) async {
    await pumpTransfer(tester, status: FileStatus.sending);
    expect(find.byType(CopyImageButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpTransfer(tester, type: FileType.pdf);
    expect(find.byType(CopyImageButton), findsNothing);
  });

  testWidgets('capture real completed transfer widgets with a synthetic Pixel file', (tester) async {
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
      await pumpTransfer(tester, brightness: brightness);
      final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/transfer-${brightness.name}${width == 900 ? '' : '-compact'}.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  }, skip: !Platform.isMacOS);
}
