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
    t = DateTime(2026, 11, 26, 17);
    c = AppController(store: MemoryStore(), now: () => t);
    await c.load();
  });
  tearDown(() => c.dispose());

  test('ohne Training: Ort und Trainingsart, fälliger Tag zuerst', () {
    final m = watchContent(c);
    expect(m['idle'], isTrue);
    expect(m['place'], 'studio');
    final days = (m['days'] as List).cast<Map>();
    expect(days.map((d) => d['id']), ['torso', 'limbs', 'gk']);
    expect(days.first['label'], 'Torso · dran');
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
    final ts = t.millisecondsSinceEpoch ~/ 1000;

    b.handle('go:torso:home');
    await pumpEventQueue();
    expect(c.workout!.place, Place.home);
    expect(sent.last['phase'], 'next');

    b.handle('pick:Liegestütze');
    await pumpEventQueue();
    expect(sent.last['phase'], 'warmup');
    expect(sent.last['warmupS'], ts);
    expect((sent.last['set'] as Map)['bw'], isTrue);

    b.handle('startSet');
    b.handle('done');
    await pumpEventQueue();
    expect(sent.last['phase'], 'log');
    expect(sent.last['restEndS'], ts + 90);
    b.handle('repsPlus');
    b.handle('cont');
    await pumpEventQueue();
    expect(sent.last['phase'], 'rest');
    b.handle('skip');
    b.handle('done');
    b.handle('end');
    b.handle('rate:passend');
    b.handle('finish');
    b.handle('save');
    await pumpEventQueue();
    expect(c.sessions.single.items.single.sets, hasLength(2));
    expect(sent.last['idle'], isTrue);
    expect(sent.last['ended'], 'saved');

    final n = sent.length;
    b.handle('hello');
    await pumpEventQueue();
    expect(sent.length, n + 1);
  });

  test('abgebrochenes Training wird auf der Uhr verworfen', () {
    c.startWorkout('torso');
    c.cancelWorkout();
    expect(watchContent(c)['ended'], 'cancelled');
  });
}
