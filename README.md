# Satzweise

Krafttraining-App für Android und iOS. Später kommt eine Garmin-Uhren-App (Venu 2) dazu.

## Stand

Grundversion der Handy-App, nach dem klickbaren Entwurf:

- **Start:** Ort wählen (Studio oder daheim) und Trainingsart wählen, also Ganzkörper, Torso / Limbs oder weitere Splits. Der fällige Split-Tag ist markiert.
- **Training:**
  - Werte sind aus dem letzten Mal vorbelegt (doppelte Progression).
  - Gerät und Notiz pro Übung.
  - Gesamt- und Satzzeit laufen sekundengenau mit.
  - Die Pause hat einen Standardwert, im Training geht ±15 s, am Ende vibriert das Handy.
- **Rückmeldung:** nach jeder Übung leicht, passend oder schwer, dazu eine Gewichtsempfehlung fürs nächste Mal.
- **Nächste Übung:** Vorschläge, gelernt aus deinen Trainings desselben Tages.
- **Zurück:** nimmt jeden Schritt im Training zurück, auch das Speichern.
- **Zusammenfassung:** Dauer, Gesamtmasse, Vergleich je Übung und eine Rückmeldung, ob du gesteigert, gehalten oder nachgelassen hast.
- **Verlauf:** Einheiten mit Typ, Ort, Dauer und Masse. Übungen über eine Auswahlliste, auch mehrere zum Vergleichen, mit Kurven und allen Sätzen.
- **Einstellungen:**
  - Standard-Pausenzeit
  - rund 45 vorgegebene Übungen, davon 14 mit Körpergewicht; je Übung einstellbar, ob sie daheim geht
  - eigene Übungen mit Piktogramm
- **Speicherung:** Daten liegen lokal auf dem Gerät. Ein laufendes Training übersteht einen Neustart der App.

- **Sperrbildschirm (Android):** normale Benachrichtigung mit bis zu zwei Reihen à drei Textknöpfen und einem breiten Knopf, je nach Schritt. Laufende Satzzeit oder Pausen-Countdown mit Balken, Gesamtzeit in der Kopfzeile. Am Pausenende Vibration und auf Wunsch ein Ton, auch bei gesperrtem Bildschirm.
- **Sätze:** keine feste Anzahl. Nach jedem Satz folgen Pause und ein neuer Satz, bis die Übung beendet wird.
- **Verlauf:** Gespeicherte Trainings lassen sich löschen.

## Garmin-Uhr (Venu 2)

Im Ordner `watch/` liegt die Connect-IQ-App für die Uhr:

- **Was die Uhr zeigt:** das laufende Training wie die Handy-App, mit denselben Knöpfen. Die obere Taste löst die Hauptaktion aus (z. B. Satz fertig), die untere nimmt den letzten Schritt zurück.
- **Training starten:** geht auch von der Uhr aus, mit Wahl zwischen Studio und daheim.
- **Aufzeichnung:** Die Uhr zeichnet das Training als Garmin-Aktivität „Krafttraining“ auf, benannt nach dem Trainingstag (z. B. „Limbs · Daheim“), mit Herzfrequenz und einer Runde je Satz. Die Aktivität geht wie gewohnt an Garmin Connect und weiter an Strava.
- **Ohne Verbindung:** Satz, Pause, Wiederholungen und Gewicht rechnet die Uhr selbst weiter. Knopfdrücke, die nicht beim Handy ankommen, schickt sie nach.
- **Handy-Seite:** `android/.../WatchBridge.kt` mit dem Connect IQ Mobile SDK und `lib/platform/watch.dart`.

Zum Bauen braucht es das Connect IQ SDK und die Gerätebeschreibung `venu2` aus Garmins SDK Manager (Anmeldung mit Garmin-Konto):

```bash
monkeyc -f watch/monkey.jungle -d venu2 -o Satzweise.prg -y developer_key.der
```

Die Datei `Satzweise.prg` kommt per USB in den Ordner `GARMIN/APPS` der Uhr.

## Geplant

1. iOS: Live Activity für den Sperrbildschirm und die Verbindung zur Uhr. Dafür braucht es einen Mac mit Xcode.

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
