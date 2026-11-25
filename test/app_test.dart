import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:satzweise/data/store.dart';
import 'package:satzweise/logic/controller.dart';
import 'package:satzweise/main.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('Training von Start bis Speichern durchtippen', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = AppController(store: MemoryStore());
    await c.load();
    await tester.pumpWidget(SatzweiseApp(c: c));
    await tester.pump();

    expect(find.text('Was trainierst du heute?'), findsOneWidget);
    expect(find.text('dran'), findsOneWidget);
    await tester.tap(find.text('Torso starten'));
    await tester.pump();

    expect(find.text('Womit startest du?'), findsOneWidget);
    await tester.tap(find.text('Bankdrücken').first);
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Satz fertig'));
      await tester.pump();
      expect(find.text('Pause läuft'), findsOneWidget);
      await tester.tap(find.text('Weiter'));
      await tester.pump();
    }
    expect(find.text('Satz 4'), findsOneWidget, reason: 'keine feste Satzzahl');
    await tester.ensureVisible(find.text('Übung beenden (3 Sätze)'));
    await tester.pump();
    await tester.tap(find.text('Übung beenden (3 Sätze)'));
    await tester.pump();
    expect(find.text('Wie hat es sich angefühlt?'), findsOneWidget);
    expect(find.textContaining('Leicht steigert schneller'), findsOneWidget);
    await tester.tap(find.text('Leicht'));
    await tester.pump();
    expect(find.text('42,5 kg'), findsOneWidget);
    await tester.tap(find.text('Übernehmen'));
    await tester.pump();

    await tester.ensureVisible(find.text('Training beenden'));
    await tester.pump();
    await tester.tap(find.text('Training beenden'));
    await tester.pump();
    expect(find.text('Erstes Training dieser Art.'), findsOneWidget);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pump();

    expect(c.sessions, hasLength(1));
    expect(find.text('Was trainierst du heute?'), findsOneWidget);

    await tester.tap(find.text('Verlauf'));
    await tester.pump();
    expect(find.textContaining('1 Übungen · 3 Sätze'), findsOneWidget);
    c.dispose();
  });
}
