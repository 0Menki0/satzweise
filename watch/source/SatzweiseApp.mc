// Satzweise für Garmin-Uhren (Venu 2).
//
// Ablauf wie in der Handy-App: Ort → Trainingsart → Übung → Aufwärmen →
// Satz → Satz eintragen (Pause läuft) → Pause → Satz … → Übung beenden →
// Rückmeldung → Übung …
//
// Die Uhr zeigt den Stand vom Handy und schickt jeden Knopfdruck dorthin.
// Aufwärmen, Satz, Eintragen und Pause rechnet sie selbst weiter, damit sie
// auch ohne Verbindung bedienbar bleibt; was nicht ankommt, wird gesammelt
// und nachgeschickt. Das Training zeichnet sie als Garmin-Aktivität
// „Krafttraining“ auf (ohne GPS); sie geht wie gewohnt an Garmin Connect und
// weiter an Strava.

import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

(:debug) const DEMO_MODE = "set";

class SatzweiseApp extends Application.AppBase {
    // Letzter Stand vom Handy (oder lokal fortgeschrieben).
    var state as Dictionary? = null;
    // Knopfdrücke, die noch nicht beim Handy angekommen sind.
    var queue as Array<String> = [] as Array<String>;
    var sending as Boolean = false;
    var connected as Boolean = false;
    var session as ActivityRecording.Session? = null;
    var restFinishedAt as Number = 0;
    // Start ohne Training: gewählter Ort (null = noch nicht gewählt).
    var pickedPlace as String? = null;
    // Testbuild mit Beispieldaten: nichts ans Handy senden.
    var demoMode as Boolean = false;
    private var _fExercise as FitContributor.Field? = null;
    private var _fReps as FitContributor.Field? = null;
    private var _fWeight as FitContributor.Field? = null;
    private var _timer as Timer.Timer? = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(params as Dictionary?) as Void {
        var cached = Storage.getValue("idle");
        if (cached instanceof Dictionary) {
            state = cached;
        }
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE] as Array<Sensor.SensorType>);
        gpsOff();
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhone));
        }
        demo();
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 1000, true);
        hello();
    }

    function onStop(params as Dictionary?) as Void {
        if (_timer != null) {
            _timer.stop();
        }
    }

    function getInitialView() {
        var view = new MainView(self);
        return [view, new MainDelegate(self, view)];
    }

    static function now() as Number {
        return Time.now().value();
    }

    function phase() as String {
        var s = state;
        if (s == null || s["idle"] == true) {
            return "idle";
        }
        var p = s["phase"];
        return p == null ? "next" : p as String;
    }

    // ------------------------------------------------------------ Handy

    function hello() as Void {
        if (!demoMode) {
            Communications.transmit({"a" => "hello", "ts" => now()}, null, new HelloListener(self));
        }
    }

    function onPhone(msg as Communications.PhoneAppMessage) as Void {
        connected = true;
        var data = msg.data;
        if (!(data instanceof Dictionary)) {
            return;
        }
        // Solange eigene Knopfdrücke unterwegs sind, ist der Stand vom Handy
        // veraltet; der nächste kommt nach dem Nachschicken.
        if (queue.size() > 0) {
            flush();
            return;
        }
        state = data;
        if (data["idle"] == true) {
            try {
                Storage.setValue("idle", data);
            } catch (e) {
                // Nur ein Zwischenspeicher für den Start ohne Handy.
            }
            var ended = data["ended"];
            if (ended != null) {
                endRecording(ended.equals("saved"));
            }
        } else {
            pickedPlace = null;
            startRecording();
        }
        WatchUi.requestUpdate();
    }

    function transmit(action as String) as Void {
        queue.add(action);
        flush();
    }

    function flush() as Void {
        if (demoMode || sending || queue.size() == 0) {
            return;
        }
        sending = true;
        Communications.transmit({"a" => queue[0], "ts" => now()}, null, new SendListener(self));
    }

    function sent(ok as Boolean) as Void {
        sending = false;
        connected = ok;
        if (ok) {
            queue = queue.slice(1, null);
            flush();
        }
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ Knöpfe

    // Führt einen Knopfdruck aus: lokal sofort sichtbar, dann ans Handy.
    function act(id as String) as Void {
        if (id.find("place:") == 0) {
            pickedPlace = id.substring(6, id.length());
            WatchUi.requestUpdate();
            return;
        }
        applyLocal(id);
        transmit(id);
        WatchUi.requestUpdate();
    }

    function applyLocal(id as String) as Void {
        var s = state;
        if (s == null) {
            return;
        }
        if (id.equals("save")) {
            endRecording(true);
            return;
        }
        var set = s["set"];
        if (!(set instanceof Dictionary)) {
            return;
        }
        var p = phase();
        var t = now();
        if (id.equals("startSet") && (p.equals("warmup") || p.equals("rest"))) {
            lap(p.equals("warmup") ? "Aufwärmen" : "Pause", 0, 0.0);
            beginSet(s, t);
        } else if (id.equals("skip") && p.equals("rest")) {
            lap("Pause", 0, 0.0);
            beginSet(s, t);
        } else if (id.equals("done") && p.equals("set")) {
            lap(set["ex"] as String, set["reps"] as Number, (set["w"] as Float).toFloat());
            s["phase"] = "log";
            s["restStartS"] = t;
            s["restEndS"] = t + (set["rest"] as Number);
            set["doneCount"] = (set["doneCount"] as Number) + 1;
        } else if (id.equals("cont") && p.equals("log")) {
            planNext(set);
            if (t < (s["restEndS"] as Number)) {
                s["phase"] = "rest";
            } else {
                lap("Pause", 0, 0.0);
                beginSet(s, t);
            }
        } else if (id.equals("end") && p.equals("log")) {
            s["phase"] = "feedback";
            s["title"] = (set["ex"] as String) + ": Wie war's?";
            s["text"] = "";
            s["rows"] = [[{"id" => "rate:leicht", "label" => "Leicht"}, {"id" => "rate:passend", "label" => "Passend", "p" => true},
                {"id" => "rate:schwer", "label" => "Schwer"}]];
            s["wide"] = null;
        } else if (id.equals("repsMinus") && (set["reps"] as Number) > 0) {
            set["reps"] = (set["reps"] as Number) - 1;
        } else if (id.equals("repsPlus")) {
            set["reps"] = (set["reps"] as Number) + 1;
        } else if (id.equals("weightMinus")) {
            var w = (set["w"] as Float) - (set["step"] as Float);
            set["w"] = w < 0 ? 0.0 : w;
        } else if (id.equals("weightPlus")) {
            set["w"] = (set["w"] as Float) + (set["step"] as Float);
        } else if (id.equals("restPlus") && (p.equals("rest") || p.equals("log"))) {
            s["restEndS"] = (s["restEndS"] as Number) + 15;
        } else if (id.equals("restMinus") && (p.equals("rest") || p.equals("log"))) {
            s["restEndS"] = (s["restEndS"] as Number) - 15;
        }
    }

    private function beginSet(s as Dictionary, t as Number) as Void {
        s["phase"] = "set";
        s["setStartS"] = t;
        s["restEndS"] = 0;
    }

    // Nächster Satz: Gewicht wie eben, Wiederholungen wie beim letzten Mal.
    private function planNext(set as Dictionary) as Void {
        set["no"] = (set["no"] as Number) + 1;
        if (set["nextReps"] != null) {
            set["reps"] = set["nextReps"];
        }
    }

    // ------------------------------------------------------------ Takt

    function tick() as Void {
        var s = state;
        var p = phase();
        if (s != null && (p.equals("rest") || p.equals("log")) && (s["restEndS"] as Number) > 0 && now() >= (s["restEndS"] as Number)) {
            // Pause vorbei: nächster Satz beginnt, auch ohne Eintragen (dann
            // gelten die vorbelegten Werte). Uhr vibriert, auf Wunsch mit Ton.
            var set = s["set"];
            if (p.equals("log") && set instanceof Dictionary) {
                planNext(set);
            }
            lap("Pause", 0, 0.0);
            beginSet(s, s["restEndS"] as Number);
            restFinishedAt = now();
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(100, 500), new Attention.VibeProfile(0, 200),
                    new Attention.VibeProfile(100, 500)] as Array<Attention.VibeProfile>);
            }
            if (s["sound"] == true && Attention has :playTone) {
                Attention.playTone(Attention.TONE_ALARM);
            }
        }
        // Ohne Verbindung nur alle 5 s neu versuchen, sonst bremst sich die
        // Uhr mit ständigen Sendeversuchen selbst aus.
        if (queue.size() > 0 && !sending && (connected || now() % 5 == 0)) {
            flush();
        }
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ Aufzeichnung

    // Krafttraining braucht keine Strecke: GPS aus, damit Garmin Connect
    // keine Karte zeigt und der Akku geschont wird.
    function gpsOff() as Void {
        if (Toybox has :Position && Position has :enableLocationEvents) {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        }
    }

    // Eine Runde abschließen: Aufwärmen, Satz (mit Übung, Wiederholungen,
    // Gewicht) oder Pause – wie beim eingebauten Krafttraining.
    function lap(name as String, reps as Number, weight as Float) as Void {
        if (session == null) {
            return;
        }
        if (_fExercise != null) {
            _fExercise.setData(name.length() > 31 ? name.substring(0, 31) : name);
            _fReps.setData(reps);
            _fWeight.setData(weight);
        }
        session.addLap();
    }

    function startRecording() as Void {
        if (session != null || !(Toybox has :ActivityRecording)) {
            return;
        }
        var s = state;
        var name = (s != null && s["day"] != null) ? s["day"] as String : "Krafttraining";
        session = ActivityRecording.createSession({
            :name => name,
            :sport => Activity.SPORT_TRAINING,
            :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
        });
        gpsOff();
        if (session has :createField) {
            _fExercise = session.createField("Uebung", 0, FitContributor.DATA_TYPE_STRING,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :count => 32});
            _fReps = session.createField("Wiederholungen", 1, FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "Wdh."});
            _fWeight = session.createField("Gewicht", 2, FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "kg"});
            _fExercise.setData("Pause");
            _fReps.setData(0);
            _fWeight.setData(0.0);
        }
        session.start();
    }

    function endRecording(save as Boolean) as Void {
        if (session == null) {
            return;
        }
        if (session.isRecording()) {
            session.stop();
        }
        if (save) {
            session.save();
        } else {
            session.discard();
        }
        session = null;
    }

    function heartRate() as Number? {
        var info = Activity.getActivityInfo();
        return info != null ? info.currentHeartRate : null;
    }

    // ------------------------------------------------------------ Testbuild

    // Nur im Testbuild (ohne -r): Beispieldaten für den Simulator.
    (:debug)
    function demo() as Void {
        demoMode = true;
        var t = now();
        var mode = DEMO_MODE;
        var set = {"ex" => "Kniebeuge", "no" => 1, "reps" => 8, "w" => 85.0, "step" => 2.5, "bw" => false, "rest" => 90,
            "doneCount" => 0, "machine" => "12", "nextReps" => 8};
        if (mode.equals("idle") || mode.equals("idle2")) {
            state = {"idle" => true, "day" => "Satzweise", "place" => "studio",
                "days" => [{"id" => "limbs", "label" => "Limbs · dran", "p" => true}, {"id" => "torso", "label" => "Torso"},
                    {"id" => "gk", "label" => "Ganzkörper"}]};
            if (mode.equals("idle2")) {
                pickedPlace = "studio";
            }
            return;
        }
        if (mode.equals("next") || mode.equals("feedback")) {
            state = {"idle" => false, "phase" => mode, "day" => "Limbs · Studio", "startS" => t - 60,
                "title" => mode.equals("next") ? "Womit startest du?" : "Kniebeuge: Wie war's?",
                "text" => "",
                "rows" => mode.equals("next")
                    ? [[{"id" => "pick:Kniebeuge", "label" => "Kniebeuge", "p" => true}, {"id" => "pick:Rumänisches Kreuzheben", "label" => "Rumän. Kreuzheben"}],
                        [{"id" => "pick:Beinpresse", "label" => "Beinpresse"}, {"id" => "undo", "label" => "Zurück"}]]
                    : [[{"id" => "rate:leicht", "label" => "Leicht"}, {"id" => "rate:passend", "label" => "Passend", "p" => true}, {"id" => "rate:schwer", "label" => "Schwer"}]],
                "wide" => mode.equals("next") ? {"id" => "cancel", "label" => "Training beenden"} : null};
            return;
        }
        if (mode.equals("log") || mode.equals("rest")) {
            set["doneCount"] = 1;
        }
        if (mode.equals("rest")) {
            set["no"] = 2;
        }
        state = {"idle" => false, "phase" => mode, "day" => "Limbs · Studio", "startS" => t - 242,
            "warmupS" => t - 134, "setStartS" => t - 42, "restStartS" => t - 6, "restEndS" => t + 84,
            "sound" => false, "rows" => [], "wide" => null, "set" => set};
    }

    (:release)
    function demo() as Void {
    }
}

class HelloListener extends Communications.ConnectionListener {
    private var _app as SatzweiseApp;

    function initialize(app as SatzweiseApp) {
        ConnectionListener.initialize();
        _app = app;
    }

    function onComplete() as Void {
        _app.connected = true;
    }

    function onError() as Void {
        _app.connected = false;
    }
}

class SendListener extends Communications.ConnectionListener {
    private var _app as SatzweiseApp;

    function initialize(app as SatzweiseApp) {
        ConnectionListener.initialize();
        _app = app;
    }

    function onComplete() as Void {
        _app.sent(true);
    }

    function onError() as Void {
        _app.sent(false);
    }
}

function getApp() as SatzweiseApp {
    return Application.getApp() as SatzweiseApp;
}
