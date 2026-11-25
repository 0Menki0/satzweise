# Satzweise

Krafttraining-App für Android und iOS. Später kommt eine Garmin-Uhren-App (Venu 2) dazu.

## Stand

Grundversion der Handy-App, nach dem klickbaren Entwurf:

- **Start:** Trainingsart wählen, also Ganzkörper, Torso / Limbs oder weitere Splits. Der fällige Split-Tag ist markiert.
- **Training:**
  - Werte sind aus dem letzten Mal vorbelegt (doppelte Progression).
  - Gerät und Notiz pro Übung.
  - Gesamt- und Satzzeit laufen sekundengenau mit.
  - Die Pause hat einen Standardwert, im Training geht ±15 s, am Ende vibriert das Handy.
- **Rückmeldung:** nach jeder Übung leicht, passend oder schwer, dazu eine Gewichtsempfehlung fürs nächste Mal.
- **Nächste Übung:** Vorschläge, gelernt aus deinen Trainings desselben Tages.
- **Zurück:** nimmt jeden Schritt im Training zurück, auch das Speichern.
- **Zusammenfassung:** Dauer, Gesamtmasse, Vergleich je Übung und eine Rückmeldung, ob du gesteigert, gehalten oder nachgelassen hast.
- **Verlauf:** Einheiten mit Typ, Dauer und Masse. Pro Übung eine Kurve, alle Sätze und ein Gerätefilter.
- **Einstellungen:**
  - Standard-Pausenzeit
  - gelernte Abläufe je Trainingsart
  - rund 30 vorgegebene Übungen
  - eigene Übungen mit Piktogramm
- **Speicherung:** Daten liegen lokal auf dem Gerät. Ein laufendes Training übersteht einen Neustart der App.

- **Sperrbildschirm (Android):** Benachrichtigung mit Satz, Pause, laufender Uhr und Knöpfen, zum Beispiel Zurück, − Wdh., Satz fertig, +15 s, Rückmeldung, nächste Übung und Speichern. Am Pausenende vibriert das Handy, auch wenn es gesperrt ist.

## Geplant

1. iOS: Live Activity für den Sperrbildschirm. Dafür braucht es einen Mac mit Xcode.
2. Garmin Venu 2: Connect-IQ-App, die die Aktivität selbst aufzeichnet. Sie läuft über Garmin Connect weiter zu Strava, gleicht sich mit dem Handy ab und funktioniert auch ohne Verbindung.

## Entwickeln

```bash
flutter test
```

```bash
flutter run
```

Vorschau im Browser mit Beispieldaten (es wird nichts gespeichert):

```bash
flutter build web --no-web-resources-cdn && cd build/web && python3 -m http.server 8765
```

Danach `http://localhost:8765/?demo` öffnen.

## Android-Version bauen

```bash
flutter build apk --release
```

Die Datei liegt danach unter `build/app/outputs/flutter-apk/app-release.apk`.

Signiert wird mit `android/satzweise-release.jks`. Die Zugangsdaten stehen in `android/key.properties`. Beide Dateien sind **nicht im Repository**, du bewahrst sie selbst auf. Fehlen sie, wird mit einem Testschlüssel signiert. Eine so gebaute Version lässt sich nicht über die installierte App spielen.

## Aufbau

- `lib/data/`: Datenmodell, Übungskatalog, Trainingsarten, Speicher
- `lib/logic/coach.dart`: Vorschläge, Vorbelegung, Empfehlung, Zusammenfassung
- `lib/logic/controller.dart`: alle Aktionen im Training samt Zurück. Sperrbildschirm und Uhr nutzen später dieselben.
- `lib/platform/lock_screen.dart`: Inhalt und Knöpfe der Sperrbildschirm-Benachrichtigung
- `android/.../WorkoutService.kt`: Vordergrunddienst mit Benachrichtigung und Vibration am Pausenende
- `lib/ui/`: Oberfläche
