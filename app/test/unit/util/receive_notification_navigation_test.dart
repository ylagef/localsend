import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/receive_notification_navigation.dart';
import 'package:localsend_isolates/model/session_status.dart';

void main() {
  test('stale pending clicks preserve every active transfer state', () {
    for (final status in SessionStatus.values) {
      expect(
        shouldOpenReceiveHistory(kind: 'pending', status: status),
        isFalse,
        reason: '$status must retain its current UI',
      );
    }
    expect(shouldOpenReceiveHistory(kind: 'pending', status: null), isFalse);
  });

  test('completion clicks cannot obscure another incoming session', () {
    for (final status in SessionStatus.values) {
      expect(
        shouldOpenReceiveHistory(kind: 'done', status: status),
        isFalse,
        reason: '$status must retain its current UI',
      );
    }
  });

  test('an idle completion opens history without resetting other navigation', () {
    expect(shouldOpenReceiveHistory(kind: 'done', status: null), isTrue);
    expect(shouldOpenReceiveHistory(kind: 'unknown', status: null), isFalse);
  });
}
