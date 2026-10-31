import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

const _channel = MethodChannel('main-delegate-channel');
final _logger = Logger('ReceiveNotifications');

Future<bool> ensureReceiveAlertsAvailable() async {
  return await _channel.invokeMethod<bool>('enableReceiveAlerts') ?? false;
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
  if (!Platform.isMacOS || !enabled) return false;
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
  if (!Platform.isMacOS) return;
  try {
    await _channel.invokeMethod<void>('removeReceiveNotification', sessionId);
  } catch (error, stack) {
    _logger.warning('Could not remove receive notification', error, stack);
  }
}

Future<void> hideReceiveAlerts() async {
  if (!Platform.isMacOS) return;
  try {
    await _channel.invokeMethod<void>('hideReceiveAlerts');
  } catch (error, stack) {
    _logger.warning('Could not hide receive alert', error, stack);
  }
}
