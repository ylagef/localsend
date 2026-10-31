import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart';
import 'package:localsend_app/util/native/receive_notifications.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/foreground_service.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:refena_flutter/refena_flutter.dart';

final androidReceiveModeProvider = NotifierProvider<AndroidReceiveMode, bool>((ref) {
  final persistence = ref.read(persistenceProvider);
  return AndroidReceiveMode(
    preferred: persistence.isAndroidReceiveMode,
    persist: persistence.setAndroidReceiveMode,
    start: () async {
      if (!Platform.isAndroid || !await requestLocalNetworkPermissionAndroid() || !await ensureReceiveAlertsAvailable()) return false;
      if (ref.read(serverProvider) == null) await ref.notifier(serverProvider).startServerFromSettings();
      if (ref.read(serverProvider) == null) return false;
      return TransferNotification.setAvailable(
        enabled: true,
        title: t.settingsTab.general.androidReceiveMode,
        text: t.settingsTab.general.androidReceiveReady,
        stopLabel: t.settingsTab.general.androidReceiveStop,
      );
    },
    stop: () async {
      if (ref.read(serverProvider)?.session?.status == SessionStatus.waiting) {
        ref.notifier(serverProvider).declineFileRequest();
      }
      await TransferNotification.setAvailable(enabled: false, title: '', text: '', stopLabel: '');
      await hideReceiveAlerts();
    },
  );
});

/// A saved preference is not proof that a service is running. Publish true only after startup succeeds.
class AndroidReceiveMode extends PureNotifier<bool> {
  final bool Function() preferred;
  final Future<void> Function(bool) persist;
  final Future<bool> Function() start;
  final Future<void> Function() stop;
  Future<void> _tail = Future.value();

  AndroidReceiveMode({required this.preferred, required this.persist, required this.start, required this.stop});

  @override
  bool init() => false;

  Future<bool> setEnabled(bool enabled, {bool save = true}) {
    final result = Completer<bool>();
    _tail = _tail.then((_) async {
      try {
        if (enabled) {
          if (!await start()) {
            state = false;
            await stop();
            result.complete(false);
            return;
          }
          try {
            if (save) await persist(true);
          } catch (_) {
            await stop();
            state = false;
            rethrow;
          }
          state = true;
        } else {
          // Deny new background sessions before withdrawing the persistent service.
          state = false;
          await stop();
          if (save) await persist(false);
        }
        result.complete(true);
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> restore() async {
    if (preferred() && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await setEnabled(true, save: false);
    }
  }

  Future<void> get pendingChanges => _tail;

  void serviceStopped() => state = false;
}

void listenAndroidReceiveMode(Ref ref) {
  ForegroundService.listen((data) {
    if (data == 'stopReceiving') {
      unawaited(ref.notifier(androidReceiveModeProvider).setEnabled(false));
    } else if (data == 'serviceStopped') {
      unawaited(
        ForegroundService.isActuallyRunning.then((running) {
          if (!running) {
            ref.notifier(androidReceiveModeProvider).serviceStopped();
            unawaited(releaseIdleAndroidReceiveEngine(ref));
          }
        }),
      );
    }
  });
}

Future<void>? _idleEngineRelease;

/// Await Rust listener shutdown before destroying Dart. An engine alone does not own their lifetime.
Future<void> releaseIdleAndroidReceiveEngine(Ref ref) {
  return _idleEngineRelease ??= _releaseIdleAndroidReceiveEngine(ref).whenComplete(() => _idleEngineRelease = null);
}

Future<void> _releaseIdleAndroidReceiveEngine(Ref ref) async {
  // Finish startup/stop and preference persistence before deciding whether the engine is idle.
  await ref.notifier(androidReceiveModeProvider).pendingChanges;
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached || ForegroundService.isRunning) return;
  await ref.notifier(serverProvider).stopServer(preserveAvailability: true);
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached || ForegroundService.isRunning) {
    await ref.notifier(serverProvider).startServerFromSettings();
    return;
  }
  await ref.redux(parentIsolateProvider).dispatchAsync(IsolateDiscoveryPauseAction());
  // Native rechecks the current Activity and service on the UI thread. If reopening won the race,
  // restore both listeners in the retained engine instead of leaving the foreground app disconnected.
  if (!await releaseDetachedReceiveEngine()) {
    await ref.notifier(serverProvider).startServerFromSettings();
    ref.redux(parentIsolateProvider).dispatch(IsolateDiscoveryResumeAction());
  }
}

/// Do not race a view reattachment against an in-flight taskless shutdown.
Future<void> resumeAndroidReceiveEngine(Ref ref) async {
  await _idleEngineRelease;
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
  await ref.notifier(androidReceiveModeProvider).restore();
  await ref.notifier(serverProvider).ensureRunning();
}
