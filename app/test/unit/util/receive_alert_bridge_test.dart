import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/macos_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('main-delegate-channel');
  const codec = StandardMethodCodec();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<dynamic> nativeCall(String method, Object? args) async {
    final reply = Completer<dynamic>();
    await messenger.handlePlatformMessage(channel.name, codec.encodeMethodCall(MethodCall(method, args)), (bytes) {
      try {
        reply.complete(bytes == null ? null : codec.decodeEnvelope(bytes));
      } catch (error) {
        reply.completeError(error);
      }
    });
    return reply.future;
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  test('native action forwards validated identity and awaits the result', () async {
    final response = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await setupMethodCallHandler(
      onReceiveAlertAction: (id, kind, action) {
        expect([id, kind, action], ['one', 'done', 'copy']);
        return response.future;
      },
    );
    final result = nativeCall('onReceiveAlertAction', {'sessionId': 'one', 'kind': 'done', 'action': 'copy'});
    response.complete({'success': true, 'message': 'Image copied'});
    expect(await result, {'success': true, 'message': 'Image copied'});
  });

  test('malformed action identity never reaches the quick-action handler', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await setupMethodCallHandler(
      onReceiveAlertAction: (_, _, _) async {
        calls++;
        return {'success': true};
      },
    );
    expect(await nativeCall('onReceiveAlertAction', {'sessionId': 7, 'kind': 'pending', 'action': 'accept'}), {'success': false});
    expect(calls, 0);
  });
}
