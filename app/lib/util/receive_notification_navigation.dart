import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/provider/android_receive_mode_provider.dart';
import 'package:localsend_app/provider/background_notifications_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/util/native/image_clipboard.dart';
import 'package:localsend_app/util/native/tray_helper.dart';
import 'package:localsend_app/util/receive_alert_actions.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Notification clicks only reveal UI. They never accept or decline a session.
Future<void> openReceiveNotification(String sessionId, String kind) async {
  if (kind != 'pending' && kind != 'done') return;
  if (!Platform.isAndroid) await showFromTray();
  // A click may have launched the app; wait for its Navigator to exist.
  await WidgetsBinding.instance.endOfFrame;
  final status = RefenaScope.defaultRef.read(serverProvider)?.session?.status;
  if (!shouldOpenReceiveHistory(kind: kind, status: status)) return;
  // Push rather than replace the root: unrelated sending/progress UI stays intact.
  // ignore: use_build_context_synchronously, unawaited_futures
  Routerino.context.pushImmediately(() => const ReceiveHistoryPage());
}

/// Old request notifications only reveal the existing UI, even after acceptance.
/// A completion may open history only when no incoming session is active.
bool shouldOpenReceiveHistory({required String kind, required SessionStatus? status}) {
  return kind == 'done' && status == null;
}

Future<Map<String, dynamic>> handleReceiveAlertAction(String sessionId, String kind, String action) async {
  try {
    if (!(Platform.isAndroid
        ? RefenaScope.defaultRef.read(androidReceiveModeProvider)
        : RefenaScope.defaultRef.read(backgroundNotificationsProvider))) {
      return {'success': false, 'message': t.settingsTab.general.alertUnavailable};
    }
    final success = await receiveAlertActions.perform(
      sessionId: sessionId,
      kind: kind,
      action: action,
      copy: copyReceivedImageToClipboard,
      open: (path) async => await const MethodChannel('main-delegate-channel').invokeMethod<bool>('openReceivedFile', path) ?? false,
      history: () => openReceiveNotification(sessionId, 'done'),
    );
    return {
      'success': success,
      'message': success && action == 'copy' ? t.settingsTab.general.alertCopied : (success ? '' : t.settingsTab.general.alertUnavailable),
    };
  } catch (_) {
    return {'success': false, 'message': t.settingsTab.general.alertActionFailed};
  }
}
