import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../logic/controller.dart';
import 'theme.dart';

String dayLabel(DateTime d) => DateFormat('E, d. MMM', 'de_DE').format(d);
String kg(double v) => '${NumberFormat.decimalPattern('de_DE').format(v.round())} kg';

class DayTag extends StatelessWidget {
  const DayTag(this.dayId, {super.key, this.suffix = ''});
  final String dayId;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c.day(dayId), borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text('${dayById(dayId).name}$suffix', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

class MachineBadge extends StatelessWidget {
  const MachineBadge(this.machine, {super.key, this.dark = false});
  final String machine;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (machine.isEmpty) return const SizedBox.shrink();
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: dark ? Colors.white : c.ink, borderRadius: BorderRadius.circular(6)),
      child: Text('Gerät $machine',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dark ? Colors.black : c.surface)),
    );
  }
}

class UndoButton extends StatelessWidget {
  const UndoButton(this.c, {super.key});
  final AppController c;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: c.undoLabel == null ? 'Nichts rückgängig zu machen' : 'Rückgängig: ${c.undoLabel}',
        child: OutlinedButton.icon(
          onPressed: c.canUndo ? c.undo : null,
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('Zurück'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), shape: const StadiumBorder()),
        ),
      );
}

/// Feld mit − und + für Wiederholungen, Gewicht oder Pausenzeit.
class StepField extends StatelessWidget {
  const StepField({
    super.key,
    required this.value,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
    this.minusLabel = '−',
    this.plusLabel = '+',
    this.semantics = '',
  });

  final String value, unit, minusLabel, plusLabel, semantics;
  final VoidCallback onMinus, onPlus;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget btn(String t, VoidCallback f, String sem) => Semantics(
          label: sem,
          button: true,
          child: SizedBox(
            width: 48,
            height: 48,
            child: TextButton(
              onPressed: f,
              style: TextButton.styleFrom(
                  backgroundColor: c.soft,
                  foregroundColor: c.ink,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        btn(minusLabel, onMinus, '$semantics verringern'),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(value, style: display(context, 26)),
            Text(unit, style: TextStyle(fontSize: 11, color: c.mute)),
          ]),
        ),
        btn(plusLabel, onPlus, '$semantics erhöhen'),
      ]),
    );
  }
}

class Hint extends StatelessWidget {
  const Hint(this.child, {super.key, this.color, this.fg});
  final Widget child;
  final Color? color, fg;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color ?? c.soft, borderRadius: BorderRadius.circular(12)),
      child: DefaultTextStyle.merge(style: TextStyle(fontSize: 13, color: fg ?? c.ink), child: child),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text(title, style: display(context, 20))),
          if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 13, color: AppColors.of(context).mute)),
        ]),
      );
}

class Kpi extends StatelessWidget {
  const Kpi(this.value, this.label, {super.key});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: display(context, 24))),
        Text(label, style: TextStyle(fontSize: 12, color: c.mute, height: 1.3)),
      ]),
    );
  }
}

/// Auswahlkarte, z. B. für Trainingsart und Tag.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({super.key, required this.title, required this.subtitle, required this.selected, required this.onTap, this.badge});
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: selected ? Color.alphaBlend(AppColors.red.withValues(alpha: .07), c.surface) : c.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), side: BorderSide(color: selected ? AppColors.red : c.line, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: display(context, 20)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: c.mute, height: 1.3)),
              ]),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(99)),
                child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
    );
  }
}
