import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/receive_alert_actions.dart';

void main() {
  late ReceiveAlertActions actions;
  late List<String> calls;
  setUp(() {
    actions = ReceiveAlertActions();
    calls = [];
  });
  Future<bool> perform(String id, String kind, String action) => actions.perform(
    sessionId: id,
    kind: kind,
    action: action,
    copy: (path) async {
      calls.add('copy:$path');
    },
    open: (path) async {
      calls.add('open:$path');
      return true;
    },
    history: () async {
      calls.add('history');
    },
  );

  test('replacement and cleared requests cannot invoke pending decisions', () async {
    actions.pending('old', (action) async {
      calls.add('old:$action');
      return true;
    });
    actions.pending('new', (action) async {
      calls.add('new:$action');
      return true;
    });
    expect(await perform('old', 'pending', 'accept'), isFalse);
    expect(await perform('new', 'done', 'accept'), isFalse);
    expect(await perform('new', 'pending', 'reject'), isTrue);
    actions.clearPending('new');
    expect(await perform('new', 'pending', 'accept'), isFalse);
    expect(calls, ['new:reject']);
  });
  test('concurrent decisions are blocked until completion', () async {
    final completer = Completer<bool>();
    actions.pending('one', (_) => completer.future);
    final first = perform('one', 'pending', 'accept');
    expect(await perform('one', 'pending', 'reject'), isFalse);
    completer.complete(true);
    expect(await first, isTrue);
  });
  test('completion actions use trusted paths and strict kind/image eligibility', () async {
    actions.completed('image', path: '/received/photo.png', image: true);
    actions.completed('file', path: '/received/file.pdf', image: false);
    expect(await perform('image', 'pending', 'copy'), isFalse);
    expect(await perform('image', 'done', 'copy'), isTrue);
    expect(await perform('file', 'done', 'copy'), isFalse);
    expect(await perform('file', 'done', 'open'), isTrue);
    expect(await perform('missing', 'done', 'history'), isFalse);
    expect(calls, ['copy:/received/photo.png', 'open:/received/file.pdf']);
  });
  test('multi-file and error cards offer review without opening arbitrary files', () async {
    actions.completed('many', path: '', image: false);
    expect(await perform('many', 'done', 'open'), isFalse);
    expect(await perform('many', 'error', 'copy'), isFalse);
    expect(await perform('many', 'error', 'history'), isTrue);
    expect(calls, ['history']);
  });
  test('old completion snapshots are bounded and evicted', () async {
    for (var i = 0; i < 9; i++) {
      actions.completed('$i', path: '/$i.png', image: true);
    }
    expect(await perform('0', 'done', 'copy'), isFalse);
    expect(await perform('8', 'done', 'copy'), isTrue);
  });
  test('failed clipboard action releases lock for retry without claiming success', () async {
    actions.completed('image', path: '/photo.png', image: true);
    await expectLater(
      actions.perform(
        sessionId: 'image',
        kind: 'done',
        action: 'copy',
        copy: (_) async {
          throw StateError('missing');
        },
        open: (_) async => false,
        history: () async {},
      ),
      throwsStateError,
    );
    expect(await perform('image', 'done', 'copy'), isTrue);
  });
}
