import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/util/foreground_service.dart';
import 'package:localsend_isolates/util/notification_strings.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('availability survives completed transfers, and disabling waits for remaining transfers', () async {
    const channel = MethodChannel('flutter_foreground_task/methods');
    final stopped = Completer<void>();
    bool running = false;
    int starts = 0;
    int stops = 0;
    Map<dynamic, dynamic>? startOptions;
    final updates = <Map<dynamic, dynamic>>[];
    FlutterForegroundTask.skipServiceResponseCheck = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isRunningService':
          return running;
        case 'checkNotificationPermission':
          return NotificationPermission.granted.index;
        case 'startService':
          running = true;
          starts++;
          startOptions = call.arguments as Map;
          return null;
        case 'updateService':
          updates.add(call.arguments as Map);
          return null;
        case 'stopService':
          running = false;
          stops++;
          stopped.complete();
          return null;
      }
      return null;
    });
    TransferNotification.init(
      NotificationStrings(
        titleReceiving: 'Receiving',
        titleSending: 'Sending',
        remainingTimeMinutes: ({required m, required ss}) => '$m:$ss',
        remainingTimeLong: ({required h, required m}) => '$h:$m',
      ),
    );
    Future<void> drain() async {
      // Starting is an awaited queue barrier, unlike progress updates and transfer releases.
      await ForegroundService.start(channelName: 'Available', title: 'Available', text: 'LAN');
    }

    expect(await TransferNotification.setAvailable(enabled: true, title: 'Available', text: 'LAN', stopLabel: 'Stop'), true);
    expect(startOptions!['serviceTypes'], [ForegroundServiceTypes.connectedDevice.rawValue]);
    expect(startOptions!.containsKey('stopWithTask'), false);
    expect(startOptions!['allowAutoRestart'], false);
    TransferNotification.start(sessionId: 'first', receiving: true);
    ForegroundService.updateNotification(title: 'Receiving', text: '100%', force: true);
    TransferNotification.stop('first');
    await drain();
    expect(running, true);
    expect(stops, 0);
    expect(starts, 1);
    expect(updates.last['notificationContentTitle'], 'Available');
    expect(updates.last['notificationContentText'], 'LAN');
    TransferNotification.start(sessionId: 'second', receiving: true);
    await TransferNotification.setAvailable(enabled: false, title: '', text: '', stopLabel: '');
    await drain();
    expect(running, true);
    expect(updates.last['buttons'], isEmpty);
    TransferNotification.stop('second');
    // Await the queued stop without starting another service.
    await stopped.future.timeout(const Duration(seconds: 2));
    expect(running, false);
    expect(stops, 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
