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

## Geplant

1. Sperrbildschirm: Benachrichtigung mit Knöpfen (Android) und Live Activity (iOS). Dazu eine Vibration zum Pausenende auch bei gesperrtem Bildschirm.
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

## Aufbau

- `lib/data/`: Datenmodell, Übungskatalog, Trainingsarten, Speicher
- `lib/logic/coach.dart`: Vorschläge, Vorbelegung, Empfehlung, Zusammenfassung
- `lib/logic/controller.dart`: alle Aktionen im Training samt Zurück. Sperrbildschirm und Uhr nutzen später dieselben.
- `lib/ui/`: Oberfläche
