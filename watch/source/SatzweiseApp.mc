// Satzweise für Garmin-Uhren (Venu 2).
//
// Die Uhr zeigt das laufende Training, wie es die Handy-App vorgibt, und
// schickt jeden Knopfdruck ans Handy. Während eines Satzes und in der Pause
// rechnet sie selbst weiter (Wiederholungen, Gewicht, Pause, Satz fertig),
// damit sie auch ohne Verbindung bedienbar bleibt. Was nicht ankommt, wird
// gesammelt und nachgeschickt. Das Training zeichnet sie als
// Garmin-Aktivität „Krafttraining“ auf; sie geht wie gewohnt an Garmin
// Connect und weiter an Strava.

import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

(:debug) const DEMO_MODE = "setRunning";

class SatzweiseApp extends Application.AppBase {
    // Letzter Stand vom Handy (oder lokal fortgeschrieben).
    var state as Dictionary? = null;
    // Knopfdrücke, die noch nicht beim Handy angekommen sind.
    var queue as Array<String> = [] as Array<String>;
    var sending as Boolean = false;
    var connected as Boolean = false;
    var session as ActivityRecording.Session? = null;
    var restFinishedAt as Number = 0;
    // Testbuild mit Beispieldaten: nichts ans Handy senden.
    var demoMode as Boolean = false;
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
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhone));
        }
        demo();
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 1000, true);
        transmit("hello");
    }

    // Nur im Testbuild (ohne -r): Beispieltraining für den Simulator.
    (:debug)
    function demo() as Void {
        if (state != null) {
            return;
        }
        demoMode = true;
        var t = now();
        var mode = DEMO_MODE;
        state = {
            "idle" => false, "title" => "Kniebeuge · Satz 2", "text" => "8 × 85 kg · Gerät 12", "day" => "Limbs · Studio",
            "status" => mode, "startS" => t - 1452, "setStartS" => t - 34,
            "restStartS" => t - 18, "restEndS" => t + 72, "sound" => false,
            "rows" => [], "wide" => null,
            "set" => {"ex" => "Kniebeuge", "no" => 2, "reps" => 8, "w" => 85.0, "step" => 2.5, "bw" => false, "rest" => 90, "doneCount" => 1}
        };
        if ("feedback".equals(mode)) {
            state = {
                "idle" => false, "title" => "Kniebeuge: Wie war's?", "text" => "8 / 8 / 7 Wdh. · 85 kg", "day" => "Limbs · Studio",
                "status" => "none", "startS" => t - 1700,
                "rows" => [[{"id" => "rate:leicht", "label" => "Leicht"}, {"id" => "rate:passend", "label" => "Passend", "p" => true}, {"id" => "rate:schwer", "label" => "Schwer"}]],
                "wide" => {"id" => "undo", "label" => "↶ Zurück"}
            };
        } else if ("idle".equals(mode)) {
            state = {
                "idle" => true, "title" => "Heute dran: Limbs", "text" => "Wo trainierst du?", "day" => "Satzweise",
                "rows" => [[{"id" => "go:limbs:studio", "label" => "Studio", "p" => true}, {"id" => "go:limbs:home", "label" => "Daheim"}]],
                "wide" => {"id" => "go:gk:studio", "label" => "Ganzkörper"}
            };
        }
    }

    (:release)
    function demo() as Void {
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

    // ------------------------------------------------------------ Handy

    function onPhone(msg as Communications.PhoneAppMessage) as Void {
        connected = true;
        var data = msg.data;
        if (!(data instanceof Dictionary)) {
            return;
        }
        // Solange eigene Knopfdrücke unterwegs sind, ist der Stand vom
        // Handy veraltet; der nächste kommt nach dem Nachschicken.
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
        applyLocal(id);
        transmit(id);
        WatchUi.requestUpdate();
    }

    function applyLocal(id as String) as Void {
        var s = state;
        if (s == null) {
            return;
        }
        var set = s["set"];
        var status = s["status"];
        if (id.equals("save")) {
            endRecording(true);
            return;
        }
        if (!(set instanceof Dictionary)) {
            return;
        }
        var t = now();
        if (id.equals("repsMinus") && (set["reps"] as Number) > 0) {
            set["reps"] = (set["reps"] as Number) - 1;
        } else if (id.equals("repsPlus")) {
            set["reps"] = (set["reps"] as Number) + 1;
        } else if (id.equals("weightMinus")) {
            var w = (set["w"] as Float) - (set["step"] as Float);
            set["w"] = w < 0 ? 0.0 : w;
        } else if (id.equals("weightPlus")) {
            set["w"] = (set["w"] as Float) + (set["step"] as Float);
        } else if (id.equals("done") && "setRunning".equals(status)) {
            if (session != null) {
                session.addLap();
            }
            s["status"] = "resting";
            s["restStartS"] = t;
            s["restEndS"] = t + (set["rest"] as Number);
            set["no"] = (set["no"] as Number) + 1;
            set["doneCount"] = (set["doneCount"] as Number) + 1;
        } else if (id.equals("skip") && "resting".equals(status)) {
            s["status"] = "setRunning";
            s["restEndS"] = t;
            s["setStartS"] = t;
        } else if (id.equals("restPlus") && "resting".equals(status)) {
            s["restEndS"] = (s["restEndS"] as Number) + 15;
        } else if (id.equals("restMinus") && "resting".equals(status)) {
            s["restEndS"] = (s["restEndS"] as Number) - 15;
        }
    }

    // ------------------------------------------------------------ Takt

    function tick() as Void {
        var s = state;
        if (s != null && "resting".equals(s["status"]) && now() >= (s["restEndS"] as Number)) {
            // Pause vorbei: Uhr vibriert, auf Wunsch mit Ton.
            s["status"] = "setRunning";
            s["setStartS"] = s["restEndS"];
            restFinishedAt = now();
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 150),
                    new Attention.VibeProfile(100, 400)] as Array<Attention.VibeProfile>);
            }
            if (s["sound"] == true && Attention has :playTone) {
                Attention.playTone(Attention.TONE_ALARM);
            }
        }
        if (queue.size() > 0 && !sending) {
            flush();
        }
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ Aufzeichnung

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
