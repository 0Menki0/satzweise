import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/controller.dart';
import '../logic/workout.dart';
import 'pictogram.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.c});
  final AppController c;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _edit(Exercise e) async {
    final m = TextEditingController(text: e.machine), n = TextEditingController(text: e.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.name),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: m, decoration: const InputDecoration(labelText: 'Standard-Gerät Nr.')),
          TextField(controller: n, decoration: const InputDecoration(labelText: 'Standard-Notiz', hintText: 'z. B. Sitz Stufe 4')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Speichern')),
        ],
      ),
    );
    if (ok == true) widget.c.editExercise(e.name, machine: m.text, note: n.text);
  }

  Future<void> _create([String name = '']) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _CreateExercisePage(c: widget.c, initialName: name)));
    search.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, col = AppColors.of(context);
    final q = search.text.trim().toLowerCase();
    final found = c.exercises.where((e) => e.name.toLowerCase().contains(q)).toList();
    final days = {for (final s in c.sessions) s.day}.toList();
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
      Text('Einstellungen', style: display(context, 30)),
      SectionTitle('Standard-Pausenzeit', trailing: 'gilt für jedes neue Training'),
      StepField(
          value: clock(c.settings.restSec),
          unit: 'min',
          semantics: 'Standard-Pausenzeit',
          minusLabel: '−15',
          plusLabel: '+15',
          onMinus: () => c.setDefaultRest(c.settings.restSec - 15),
          onPlus: () => c.setDefaultRest(c.settings.restSec + 15)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: [
        for (final p in [60, 90, 120, 180])
          ChoiceChip(label: Text(clock(p)), selected: c.settings.restSec == p, onSelected: (_) => c.setDefaultRest(p)),
      ]),
      const SizedBox(height: 6),
      Text('Im Training passt du sie mit −15 / +15 s an.', style: TextStyle(fontSize: 13, color: col.mute)),
      if (days.isNotEmpty) ...[
        const SectionTitle('Gelernte Abläufe', trailing: 'aus deinen Trainings'),
        for (final d in days)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: col.soft, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DayTag(d, suffix: ' · aus ${c.sessions.where((s) => s.day == d).length} Trainings'),
              const SizedBox(height: 4),
              Text(usualOrder(c.sessions, d).join(' → ').ifEmpty('noch zu wenige Daten'), style: const TextStyle(fontSize: 13)),
            ]),
          ),
      ],
      SectionTitle('Meine Übungen', trailing: '${c.selected.length} ausgewählt'),
      TextField(
        controller: search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            hintText: 'Übung suchen',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      ),
      if (found.isEmpty) ...[
        const SizedBox(height: 10),
        Hint(Text('Keine Übung „${search.text.trim()}“ gefunden.')),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => _create(search.text.trim()), child: Text('„${search.text.trim()}“ als eigene Übung anlegen')),
      ],
      for (final g in MuscleGroup.values)
        if (found.any((e) => e.group == g)) ...[
          Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 2),
              child: Text(g.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: col.mute))),
          for (final e in found.where((e) => e.group == g)) _ExerciseRow(c: c, e: e, onEdit: () => _edit(e)),
        ],
      const SizedBox(height: 14),
      OutlinedButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Eigene Übung erstellen')),
    ]);
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.c, required this.e, required this.onEdit});
  final AppController c;
  final Exercise e;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final col = AppColors.of(context);
    final counts = dayCounts(c.sessions, e.name).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: col.line))),
      child: Row(children: [
        Pictogram(kind: pictogramFor(e, e.name)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              MachineBadge(e.machine),
            ]),
            Text(
                '${e.repMin}–${e.repMax} Wdh. · +${fmtKg(e.step)} kg${e.custom ? ' · eigene' : ''}${e.note.isEmpty ? '' : ' · ${e.note}'}',
                style: TextStyle(fontSize: 13, color: col.mute)),
            if (counts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Wrap(spacing: 10, children: [for (final x in counts) DayTag(x.key, suffix: ' ${x.value}×')]),
              ),
          ]),
        ),
        IconButton(onPressed: onEdit, tooltip: 'Gerät und Notiz bearbeiten', icon: const Icon(Icons.edit_outlined)),
        IconButton.filled(
          onPressed: () => c.toggleSelected(e.name),
          tooltip: e.selected ? 'Aus Auswahl entfernen' : 'Zur Auswahl hinzufügen',
          style: IconButton.styleFrom(
              backgroundColor: e.selected ? AppColors.red : col.surface,
              foregroundColor: e.selected ? Colors.white : col.ink,
              side: BorderSide(color: e.selected ? AppColors.red : col.line)),
          icon: Icon(e.selected ? Icons.check : Icons.add),
        ),
      ]),
    );
  }
}

class _CreateExercisePage extends StatefulWidget {
  const _CreateExercisePage({required this.c, required this.initialName});
  final AppController c;
  final String initialName;

  @override
  State<_CreateExercisePage> createState() => _CreateExercisePageState();
}

class _CreateExercisePageState extends State<_CreateExercisePage> {
  late final name = TextEditingController(text: widget.initialName);
  final repMin = TextEditingController(text: '8'), repMax = TextEditingController(text: '12');
  final weight = TextEditingController(text: '20'), step = TextEditingController(text: '2,5');
  final machine = TextEditingController(), note = TextEditingController();
  MuscleGroup group = MuscleGroup.brust;
  String? pictogram;
  String? error;

  double? _num(TextEditingController t) => double.tryParse(t.text.replaceAll(',', '.'));

  void _save() {
    final err = widget.c.addCustomExercise(
      name: name.text,
      group: group,
      repMin: int.tryParse(repMin.text) ?? 0,
      repMax: int.tryParse(repMax.text) ?? 0,
      startWeight: _num(weight) ?? -1,
      step: _num(step) ?? 0,
      machine: machine.text,
      note: note.text,
      pictogram: pictogram,
    );
    if (err != null) {
      setState(() => error = err);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration d(String l, [String? h]) => InputDecoration(labelText: l, hintText: h, border: const OutlineInputBorder());
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))];
    final preview = pictogram ?? pictogramFor(Exercise(name: '', group: group, repMin: 1, repMax: 1, step: 1, startWeight: 0), '');
    return Scaffold(
      appBar: AppBar(title: const Text('Eigene Übung')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        TextField(controller: name, autofocus: widget.initialName.isEmpty, decoration: d('Name')),
        const SizedBox(height: 12),
        DropdownButtonFormField<MuscleGroup>(
          initialValue: group,
          decoration: d('Muskelgruppe'),
          items: [for (final g in MuscleGroup.values) DropdownMenuItem(value: g, child: Text(g.label))],
          onChanged: (g) => setState(() => group = g!),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: repMin, keyboardType: TextInputType.number, inputFormatters: numbers, decoration: d('Wdh. von'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: repMax, keyboardType: TextInputType.number, inputFormatters: numbers, decoration: d('bis'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: weight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: numbers,
                  decoration: d('Startgewicht kg'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: step,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: numbers,
                  decoration: d('Steigerung kg'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(width: 120, child: TextField(controller: machine, decoration: d('Gerät Nr.', 'optional'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: note, decoration: d('Notiz', 'optional'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Pictogram(kind: preview, size: 58),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: pictogram,
              decoration: d('Piktogramm'),
              items: [
                const DropdownMenuItem(value: null, child: Text('nach Muskelgruppe')),
                for (final p in pictogramNames.entries) DropdownMenuItem(value: p.key, child: Text(p.value)),
              ],
              onChanged: (p) => setState(() => pictogram = p),
            ),
          ),
        ]),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: AppColors.red))),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
