import 'dart:io';

import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

final _channel = MethodChannel(Platform.isAndroid ? 'org.localsend.localsend_app/receive' : 'main-delegate-channel');
final _logger = Logger('ReceiveNotifications');

Future<bool> ensureReceiveAlertsAvailable() async {
  if (Platform.isAndroid && !await Permission.notification.request().isGranted) return false;
  return await _channel.invokeMethod<bool>(
        'enableReceiveAlerts',
        Platform.isAndroid ? {'channelName': t.settingsTab.general.androidReceiveMode} : null,
      ) ??
      false;
}

/// Only reports success if the native card was shown while the app was backgrounded.
/// Notification errors must never fail a transfer or suppress its normal fallback UI.
Future<bool> showReceiveNotification({
  required bool enabled,
  required String sessionId,
  required String kind,
  required String title,
  required String body,
  Map<String, String> details = const {},
}) async {
  if ((!Platform.isMacOS && !Platform.isAndroid) || !enabled) return false;
  try {
    return await _channel
            .invokeMethod<bool>('showReceiveNotification', {
              'sessionId': sessionId,
              'kind': kind,
              'title': title,
              'body': body,
              ...details,
            })
            .timeout(const Duration(seconds: 3)) ??
        false;
  } catch (error, stack) {
    _logger.warning('Could not schedule receive notification', error, stack);
    return false;
  }
}

Future<void> removeReceiveNotification(String sessionId) async {
  if (!Platform.isMacOS && !Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>('removeReceiveNotification', sessionId);
  } catch (error, stack) {
    _logger.warning('Could not remove receive notification', error, stack);
  }
}

Future<void> hideReceiveAlerts() async {
  if (!Platform.isMacOS && !Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>('hideReceiveAlerts');
  } catch (error, stack) {
    _logger.warning('Could not hide receive alert', error, stack);
  }
}

void setupAndroidReceiveNotifications({
  required Future<void> Function(String, String) onOpen,
  required Future<Map<String, dynamic>> Function(String, String, String) onAction,
}) {
  _channel.setMethodCallHandler((call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
    final sessionId = args['sessionId'];
    final kind = args['kind'];
    if (sessionId is! String || kind is! String) return {'success': false};
    if (call.method == 'onReceiveAlertAction' && args['action'] is String) {
      return onAction(sessionId, kind, args['action'] as String);
    }
    if (call.method == 'onNotificationClicked') await onOpen(sessionId, kind);
    return null;
  });
  _channel.invokeMethod<void>('receiveNotificationsReady'); // ignore: discarded_futures
}

/// Release a taskless engine after its last foreground-service owner stops.
Future<bool> releaseDetachedReceiveEngine() async {
  if (!Platform.isAndroid) return false;
  return await _channel.invokeMethod<bool>('releaseDetachedEngine') ?? false;
}
