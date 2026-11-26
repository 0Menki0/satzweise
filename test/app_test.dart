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

    Future<void> tap(String text) async {
      await tester.ensureVisible(find.text(text).first);
      await tester.pump();
      await tester.tap(find.text(text).first);
      await tester.pump();
    }

    expect(find.text('Wo trainierst du heute?'), findsOneWidget);
    await tap('Im Studio');
    expect(find.text('Was trainierst du?'), findsOneWidget);
    expect(find.text('dran'), findsOneWidget);
    await tap('Torso');

    expect(find.text('Womit startest du?'), findsOneWidget);
    await tap('Bankdrücken');
    expect(find.text('Aufwärmen'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tap('Satz starten'.replaceAll('Satz starten', i == 0 ? 'Satz starten' : 'Pause beenden'));
      expect(find.text('Satz läuft'), findsOneWidget);
      await tap('Satz beenden');
      expect(find.text('Wie lief Satz ${i + 1}?'), findsOneWidget);
      expect(find.text('Pause läuft'), findsOneWidget);
      if (i < 2) await tap('Weiter');
    }
    await tap('Übung beenden (3 Sätze)');
    expect(find.text('Wie war\'s?'), findsOneWidget);
    await tap('Leicht');
    expect(find.textContaining('nächstes Mal 42,5 kg'), findsOneWidget);
    expect(find.text('Als Nächstes?'), findsOneWidget);

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
    expect(find.text('Wo trainierst du heute?'), findsOneWidget);

    await tester.tap(find.text('Verlauf'));
    await tester.pump();
    expect(find.textContaining('1 Übungen · 3 Sätze'), findsOneWidget);
    c.dispose();
  });
}
