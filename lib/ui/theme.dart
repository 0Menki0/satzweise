import 'package:material_ui/material_ui.dart';

/// Farben in Anlehnung an Hantelscheiben: Rot führt, Blau begleitet.
class AppColors {
  const AppColors._(this.dark);
  final bool dark;

  static const red = Color(0xFFE2322B);
  static const blueLight = Color(0xFF1F5FBF);
  static const blueDark = Color(0xFF5B93EA);

  static AppColors of(BuildContext context) => AppColors._(Theme.of(context).brightness == Brightness.dark);

  Color get bg => dark ? const Color(0xFF121212) : const Color(0xFFF4F2EE);
  Color get surface => dark ? const Color(0xFF1B1B1B) : Colors.white;
  Color get soft => dark ? const Color(0xFF262523) : const Color(0xFFF3F1ED);
  Color get ink => dark ? const Color(0xFFF1EFEA) : const Color(0xFF151515);
  Color get mute => dark ? const Color(0xFFA19D96) : const Color(0xFF6B6862);
  Color get line => dark ? const Color(0xFF2C2B29) : const Color(0xFFDEDAD3);
  Color get blue => dark ? blueDark : blueLight;
  Color get green => dark ? const Color(0xFF43C27D) : const Color(0xFF1D8A4D);
  Color get amber => dark ? const Color(0xFFF0A43A) : const Color(0xFFB86E00);

  /// Farbe eines Trainingstags im Verlauf.
  Color day(String id) => switch (id) {
        'torso' => red,
        'limbs' => blue,
        'gk' => ink,
        'push' => red,
        'pull' => blue,
        'beine' => green,
        'ok' => red,
        'uk' => blue,
        _ => mute,
      };
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final c = AppColors._(dark);
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.red, brightness: b).copyWith(
    primary: AppColors.red,
    onPrimary: Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    secondary: c.blue,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.surface,
    dividerColor: c.line,
    textTheme: Typography.material2021(platform: TargetPlatform.android).englishLike.apply(bodyColor: c.ink, displayColor: c.ink),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: c.ink,
        side: BorderSide(color: c.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(shape: StadiumBorder(side: BorderSide(color: c.line))),
    navigationBarTheme: NavigationBarThemeData(indicatorColor: AppColors.red.withValues(alpha: .14)),
  );
}

/// Große Zahlen und Überschriften in schmaler Schrift, wie auf Hallenschildern.
TextStyle display(BuildContext context, double size, {Color? color, FontWeight weight = FontWeight.w700}) => TextStyle(
      fontSize: size,
      height: 1.05,
      fontWeight: weight,
      letterSpacing: -.5,
      color: color ?? AppColors.of(context).ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
