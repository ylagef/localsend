import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/android_receive_mode_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  late RefenaContainer container;
  late AndroidReceiveMode controller;
  late bool preference;
  late bool canStart;
  late bool failPersistence;
  late int stops;
  Future<bool> Function()? startOverride;

  setUp(() {
    preference = false;
    canStart = true;
    failPersistence = false;
    stops = 0;
    startOverride = null;
    controller = AndroidReceiveMode(
      preferred: () => preference,
      persist: (enabled) async {
        if (failPersistence) throw StateError('disk full');
        preference = enabled;
      },
      start: () => startOverride?.call() ?? Future.value(canStart),
      stop: () async {
        stops++;
      },
    );
    container = RefenaContainer(overrides: [androidReceiveModeProvider.overrideWithNotifier((_) => controller)]);
  });
  tearDown(() => container.dispose(androidReceiveModeProvider));

  test('saved preference does not claim a service is already running', () {
    preference = true;
    expect(container.read(androidReceiveModeProvider), false);
  });

  test('startup failure never persists or advertises availability', () async {
    canStart = false;
    expect(await container.notifier(androidReceiveModeProvider).setEnabled(true), false);
    expect(container.read(androidReceiveModeProvider), false);
    expect(preference, false);
  });

  test('confirmed startup enables mode; disable stops service and persists off', () async {
    expect(await container.notifier(androidReceiveModeProvider).setEnabled(true), true);
    expect(container.read(androidReceiveModeProvider), true);
    expect(preference, true);
    await controller.setEnabled(false);
    expect(container.read(androidReceiveModeProvider), false);
    expect(preference, false);
    expect(stops, 1);
  });

  test('failed persistence rolls back the running service', () async {
    failPersistence = true;
    await expectLater(container.notifier(androidReceiveModeProvider).setEnabled(true), throwsStateError);
    expect(container.read(androidReceiveModeProvider), false);
    expect(stops, 1);
  });

  test('stop queued during startup wins and does not leave a live service', () async {
    final start = Completer<bool>();
    startOverride = () => start.future;
    final enable = container.notifier(androidReceiveModeProvider).setEnabled(true);
    final disable = controller.setEnabled(false);
    expect(container.read(androidReceiveModeProvider), false);
    start.complete(true);
    await enable;
    await disable;
    expect(container.read(androidReceiveModeProvider), false);
    expect(preference, false);
    expect(stops, 1);
  });

  test('temporary suspension and service loss preserve preference for next open', () async {
    await container.notifier(androidReceiveModeProvider).setEnabled(true);
    controller.serviceStopped();
    expect(container.read(androidReceiveModeProvider), false);
    expect(preference, true);
    await controller.setEnabled(false, save: false);
    expect(preference, true);
  });
}
