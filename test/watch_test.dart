import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:satzweise/data/models.dart';
import 'package:satzweise/data/store.dart';
import 'package:satzweise/logic/controller.dart';
import 'package:satzweise/platform/watch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('de_DE'));

  late DateTime t;
  late AppController c;
  setUp(() async {
    t = DateTime(2026, 11, 25, 17);
    c = AppController(store: MemoryStore(), now: () => t);
    await c.load();
  });
  tearDown(() => c.dispose());

  List<String> ids(Map<String, Object?> m) => [
        for (final r in m['rows'] as List)
          for (final b in r as List) (b as Map)['id'] as String,
        if (m['wide'] != null) (m['wide'] as Map)['id'] as String,
      ];

  test('ohne Training: Start von der Uhr, mit Studio und daheim', () {
    final m = watchContent(c);
    expect(m['idle'], isTrue);
    expect(m['title'], 'Heute dran: Torso');
    expect(ids(m), ['go:torso:studio', 'go:torso:home', 'go:gk:studio']);
  });

  test('Training komplett von der Uhr aus, inklusive Start', () async {
    final sent = <Map>[];
    const ch = MethodChannel('test/watch');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (m) async {
      if (m.method == 'send') sent.add(m.arguments as Map);
      return m.method == 'pendingActions' ? <String>[] : null;
    });
    final b = WatchBridge(c, channel: ch);
    await b.start();
    expect(sent.single['idle'], isTrue);

    b.handle('go:torso:home');
    await pumpEventQueue();
    expect(c.workout!.place, Place.home);
    expect(sent.last['day'], 'Torso · Daheim');

    b.handle('pick:Liegestütze');
    await pumpEventQueue();
    final s = sent.last;
    expect(s['status'], 'setRunning');
    expect(s['set'], containsPair('ex', 'Liegestütze'));
    expect((s['set'] as Map)['bw'], isTrue);
    expect(s['startS'], t.millisecondsSinceEpoch ~/ 1000);

    b.handle('repsPlus');
    b.handle('done');
    await pumpEventQueue();
    expect(sent.last['status'], 'resting');
    expect(sent.last['restEndS'], (t.millisecondsSinceEpoch ~/ 1000) + 90);
    b.handle('end');
    b.handle('rate:passend');
    b.handle('accept');
    b.handle('finish');
    b.handle('save');
    await pumpEventQueue();
    expect(c.sessions.single.place, Place.home);
    expect(sent.last['idle'], isTrue);
    expect(sent.last['ended'], 'saved', reason: 'Uhr speichert daraufhin ihre Aufzeichnung');

    final n = sent.length;
    b.handle('hello');
    await pumpEventQueue();
    expect(sent.length, n + 1, reason: 'neu gestartete Uhr bekommt den Stand erneut');
  });

  test('abgebrochenes Training wird auf der Uhr verworfen', () {
    c.startWorkout('torso');
    c.cancelWorkout();
    expect(watchContent(c)['ended'], 'cancelled');
  });
}
