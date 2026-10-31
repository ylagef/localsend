import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/receive_notifications.dart';
import 'package:refena_flutter/refena_flutter.dart';

final backgroundNotificationsProvider = NotifierProvider<BackgroundNotificationsService, bool>((ref) {
  return BackgroundNotificationsService(
    ref.read(persistenceProvider),
    ensureAvailable: ensureReceiveAlertsAvailable,
    keepRunning: () => ref.notifier(settingsProvider).setMinimizeToTray(true),
    hideAlerts: hideReceiveAlerts,
  );
});

class BackgroundNotificationsService extends PureNotifier<bool> {
  final PersistenceService persistence;
  final Future<bool> Function() ensureAvailable;
  final Future<void> Function() keepRunning;
  final Future<void> Function()? hideAlerts;

  BackgroundNotificationsService(this.persistence, {required this.ensureAvailable, required this.keepRunning, this.hideAlerts});

  @override
  bool init() => persistence.isBackgroundNotifications();

  /// Native availability failure never changes the existing tray preference or the enabled setting.
  Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      if (!await ensureAvailable()) return false;
      await keepRunning();
    }
    await persistence.setBackgroundNotifications(enabled);
    state = enabled;
    if (!enabled) await hideAlerts?.call();
    return true;
  }
}
