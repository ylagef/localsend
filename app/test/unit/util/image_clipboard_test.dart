import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/image_clipboard.dart';
import 'package:localsend_isolates/model/file_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('main-delegate-channel');

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('copy is offered only for a macOS image with a file path', () {
    expect(canCopyReceivedImage(fileType: FileType.image, path: '/received.png', isMacOS: true), isTrue);
    for (final type in FileType.values.where((type) => type != FileType.image)) {
      expect(canCopyReceivedImage(fileType: type, path: '/file', isMacOS: true), isFalse);
    }
    expect(canCopyReceivedImage(fileType: FileType.image, path: null, isMacOS: true), isFalse);
    expect(canCopyReceivedImage(fileType: FileType.image, path: '', isMacOS: true), isFalse);
    expect(canCopyReceivedImage(fileType: FileType.image, path: '/received.png', isMacOS: false), isFalse);
  });

  test('passes the received path to native image copying', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    await copyReceivedImageToClipboard('/received.png');
    expect(received!.method, 'copyImageToClipboard');
    expect(received!.arguments, '/received.png');
  });

  test('native image failures propagate to the UI', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'IMAGE_COPY_FAILED');
    });
    await expectLater(copyReceivedImageToClipboard('/missing.png'), throwsA(isA<PlatformException>()));
  });
}
