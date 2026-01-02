import 'package:flutter_test/flutter_test.dart';
import 'package:pagetmb/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PageTMBApp());

    // Verify that the app title is present.
    expect(find.textContaining('PageTMB'), findsOneWidget);
  });
}
