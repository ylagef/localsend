import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/widget/copy_image_button.dart';

void main() {
  const channel = MethodChannel('main-delegate-channel');
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  Future<void> pumpButton(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: CopyImageButton(path: '/received.png')),
    ),
  );

  testWidgets('awaits copying and blocks repeat activation until completion', (tester) async {
    final complete = Completer<void>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      await complete.future;
      return null;
    });
    await pumpButton(tester);
    expect(find.byTooltip(t.receiveHistoryPage.entryActions.copyImage), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    expect(find.text(t.general.copiedToClipboard), findsNothing);
    await tester.tap(find.byType(IconButton));
    expect(calls, 1);
    complete.complete();
    await tester.pumpAndSettle();
    expect(find.text(t.general.copiedToClipboard), findsOneWidget);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNotNull);
  });

  testWidgets('reports failure without a success message and permits retry', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'IMAGE_COPY_FAILED');
    });
    await pumpButton(tester);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text(t.general.error), findsOneWidget);
    expect(find.text(t.general.copiedToClipboard), findsNothing);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNotNull);
  });

  testWidgets('finishing after navigation does not update a disposed widget', (tester) async {
    final complete = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      await complete.future;
      return null;
    });
    await pumpButton(tester);
    await tester.tap(find.byType(IconButton));
    await tester.pumpWidget(const SizedBox());
    complete.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
