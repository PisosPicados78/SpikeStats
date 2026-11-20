import 'package:flutter_test/flutter_test.dart';
import 'package:volleyball_scouting/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VolleyballScoutingApp());
  });
}
