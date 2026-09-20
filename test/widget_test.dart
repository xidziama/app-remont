import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke test can render a lightweight widget', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('APP Remont'),
        ),
      ),
    );

    expect(find.text('APP Remont'), findsOneWidget);
  });
}
