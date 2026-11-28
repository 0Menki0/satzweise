import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'data/store.dart';
import 'logic/controller.dart';
import 'platform/lock_screen.dart';
import 'platform/watch.dart';
import 'ui/history_tab.dart';
import 'ui/settings_tab.dart';
import 'ui/theme.dart';
import 'ui/training_tab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  // Im Browser (nur Vorschau) wird nichts dauerhaft gespeichert.
  final c = AppController(store: kIsWeb ? MemoryStore() : FileStore());
  final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  // Auf Android vibriert der Trainingsdienst am Pausenende, auch bei
  // gesperrtem Bildschirm. Sonst kurz über die App, solange sie offen ist.
  if (!android) {
    c.onRestFinished = () {
      HapticFeedback.heavyImpact();
      if (c.settings.restSound) SystemSound.play(SystemSoundType.alert);
    };
  }
  runApp(SatzweiseApp(c: c));
  // Web-Vorschau: Bedienhilfen an, damit sich die Vorschau per Skript bedienen lässt.
  if (kIsWeb && Uri.base.queryParameters.containsKey('demo')) SemanticsBinding.instance.ensureSemantics();
  await c.load(demo: kIsWeb && Uri.base.queryParameters.containsKey('demo'));
  if (android) {
    await LockScreenBridge(c).start();
    await WatchBridge(c).start();
  }
}

class SatzweiseApp extends StatelessWidget {
  const SatzweiseApp({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Satzweise',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('de', 'DE'),
        supportedLocales: const [Locale('de', 'DE')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: HomeShell(c: c),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.c});
  final AppController c;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.c,
        builder: (context, _) {
          final c = widget.c;
          if (!c.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          return Scaffold(
            body: SafeArea(
              child: IndexedStack(index: tab, children: [
                TrainingTab(c: c, openSettings: () => setState(() => tab = 2)),
                HistoryTab(c: c),
                SettingsTab(c: c),
              ]),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.fitness_center), label: 'Training'),
                NavigationDestination(icon: Icon(Icons.show_chart), label: 'Verlauf'),
                NavigationDestination(icon: Icon(Icons.tune), label: 'Einstellungen'),
              ],
            ),
          );
        },
      );
}
