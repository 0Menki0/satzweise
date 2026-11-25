import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Ein Knopf auf dem Bildschirm: Rechteck und Aktion.
class Hit {
    var x as Number;
    var y as Number;
    var w as Number;
    var h as Number;
    var id as String;

    function initialize(x as Number, y as Number, w as Number, h as Number, id as String) {
        self.x = x;
        self.y = y;
        self.w = w;
        self.h = h;
        self.id = id;
    }
}

// Große Knöpfe: im Satz und in der Pause zwei Knöpfe plus ein großer
// Hauptknopf; alles Weitere (Gewicht, Übung beenden, Zurück) auf einer
// zweiten Seite („mehr“ oder nach oben wischen). Die übrigen Schritte
// zeigen ihre Knöpfe untereinander in voller Breite.
class MainView extends WatchUi.View {
    const RED = 0xE2322B;
    const BLUE = 0x5B93EA;
    const GREEN = 0x1D8A4D;
    const GREY = 0x333336;
    const PRESSED = 0x6A6A70;
    const MUTE = 0xA0A0A8;

    private var _app as SatzweiseApp;
    var hits as Array<Hit> = [] as Array<Hit>;
    var primary as String? = null;

    // 0 = Hauptseite, 1 = „mehr“.
    var page as Number = 0;
    private var _lastStatus as String = "";

    // Kurzes Aufleuchten des gedrückten Knopfs.
    var pressedId as String? = null;
    var pressedAt as Number = 0;

    function initialize(app as SatzweiseApp) {
        View.initialize();
        _app = app;
    }

    static function clock(sec as Number) as String {
        if (sec < 0) {
            sec = 0;
        }
        var h = sec / 3600;
        var m = (sec % 3600) / 60;
        var s = sec % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%d") + ":" + s.format("%02d");
    }

    static function kg(w as Float) as String {
        var r = Math.round(w * 100) / 100.0;
        var t = (r == r.toNumber()) ? r.toNumber().format("%d") : r.format("%.2f");
        if (t.find(".") != null) {
            while (t.substring(t.length() - 1, t.length()).equals("0")) {
                t = t.substring(0, t.length() - 1);
            }
            var i = t.find(".");
            t = t.substring(0, i) + "," + t.substring(i + 1, t.length());
        }
        return t;
    }

    static function setText(set as Dictionary) as String {
        var reps = (set["reps"] as Number).format("%d");
        var w = set["w"] as Float;
        if (set["bw"] == true) {
            return w == 0 ? reps + " Wdh." : reps + " Wdh. + " + kg(w) + " kg";
        }
        return reps + " × " + kg(w) + " kg";
    }

    function press(id as String) as Void {
        pressedId = id;
        pressedAt = System.getTimer();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        hits = [] as Array<Hit>;
        primary = null;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var s = _app.state;
        if (s == null) {
            dc.drawText(cx, h * 0.4, Graphics.FONT_MEDIUM, "Satzweise", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(MUTE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.56, Graphics.FONT_TINY, "Öffne Satzweise\nauf dem Handy", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var now = SatzweiseApp.now();
        var status = s["status"] as String?;
        var idle = s["idle"] == true;
        var statusKey = idle ? "idle" : (status == null ? "none" : status) + (s["title"] as String);
        if (!statusKey.equals(_lastStatus)) {
            // Neuer Schritt: zurück auf die Hauptseite.
            page = 0;
            _lastStatus = statusKey;
        }

        // Kopf: Tag, Gesamtzeit, Puls bzw. Verbindung.
        var head = s["day"] != null ? s["day"] as String : "Satzweise";
        if (!idle && s["startS"] != null) {
            head = head + " · " + clock(now - (s["startS"] as Number));
        }
        dc.setColor(MUTE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 34, Graphics.FONT_XTINY, head, Graphics.TEXT_JUSTIFY_CENTER);
        var line2 = "";
        if (_app.sending) {
            line2 = "sendet …";
        } else if (_app.queue.size() > 0 && !_app.connected) {
            line2 = "offline, " + _app.queue.size().format("%d") + " offen";
        } else {
            var hr = _app.heartRate();
            if (hr != null) {
                line2 = "Puls " + hr.format("%d");
            }
        }
        if (line2.length() > 0) {
            dc.setColor(RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 62, Graphics.FONT_XTINY, line2, Graphics.TEXT_JUSTIFY_CENTER);
        }

        var set = s["set"] as Dictionary?;
        if (set != null && ("setRunning".equals(status) || "resting".equals(status))) {
            if (page == 1) {
                drawMore(dc, s, set, w, h);
            } else if ("setRunning".equals(status)) {
                drawSet(dc, s, set, now, w, h);
            } else {
                drawRest(dc, s, set, now, w, h);
            }
            return;
        }

        // Übrige Schritte: Titel, Text, Knöpfe untereinander.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 100, Graphics.FONT_SMALL, s["title"] as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (s["text"] != null) {
            dc.setColor(MUTE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 138, Graphics.FONT_XTINY, s["text"] as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        var list = [] as Array<Dictionary>;
        var rows = s["rows"] as Array?;
        if (rows != null) {
            for (var r = 0; r < rows.size(); r++) {
                var row = rows[r] as Array;
                for (var i = 0; i < row.size(); i++) {
                    list.add(row[i] as Dictionary);
                }
            }
        }
        if (s["wide"] != null) {
            list.add(s["wide"] as Dictionary);
        }
        var n = list.size() > 4 ? 4 : list.size();
        var bh = n <= 3 ? 60 : 48;
        var gap = n <= 3 ? 8 : 6;
        var y = 168;
        for (var i = 0; i < n; i++) {
            button(dc, list[i], (w - 300) / 2, y, 300, bh, w, h, Graphics.FONT_SMALL);
            y += bh + gap;
        }
    }

    private function drawSet(dc as Graphics.Dc, s as Dictionary, set as Dictionary, now as Number, w as Number, h as Number) as Void {
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 94, Graphics.FONT_SMALL, set["ex"] as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var fresh = now - _app.restFinishedAt < 5;
        var info = "Satz " + (set["no"] as Number).format("%d");
        if (s["setStartS"] != null) {
            info = info + " · " + clock(now - (s["setStartS"] as Number));
        }
        dc.setColor(fresh ? GREEN : MUTE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 136, Graphics.FONT_XTINY, fresh ? "Pause vorbei · los!" : info, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(0xFF6A62, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 178, Graphics.FONT_LARGE, setText(set), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        pair(dc, {"id" => "repsMinus", "label" => "- Wdh."}, {"id" => "repsPlus", "label" => "+ Wdh."}, 218, w, h);
        button(dc, {"id" => "done", "label" => "Satz fertig", "p" => true}, (w - 300) / 2, 292, 300, 68, w, h, Graphics.FONT_MEDIUM);
        moreLink(dc, "mehr", w, h);
    }

    private function drawRest(dc as Graphics.Dc, s as Dictionary, set as Dictionary, now as Number, w as Number, h as Number) as Void {
        var cx = w / 2;
        var end = s["restEndS"] as Number;
        var start = s["restStartS"] as Number;
        var total = end - start;
        var left = end - now;
        if (total > 0) {
            // Ring am Rand läuft rückwärts.
            dc.setPenWidth(10);
            dc.setColor(0x1F2D45, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, h / 2, cx - 8);
            dc.setColor(BLUE, Graphics.COLOR_TRANSPARENT);
            var deg = 360.0 * left / total;
            if (deg > 0.5) {
                dc.drawArc(cx, h / 2, cx - 8, Graphics.ARC_COUNTER_CLOCKWISE, 90, (90 + deg).toNumber());
            }
            dc.setPenWidth(1);
        }
        dc.setColor(MUTE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 96, Graphics.FONT_XTINY, "Pause · danach Satz " + (set["no"] as Number).format("%d"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 145, Graphics.FONT_NUMBER_MEDIUM, clock(left), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 192, Graphics.FONT_XTINY, setText(set), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        pair(dc, {"id" => "restMinus", "label" => "-15 s"}, {"id" => "restPlus", "label" => "+15 s"}, 218, w, h);
        button(dc, {"id" => "skip", "label" => "Weiter", "p" => true}, (w - 300) / 2, 292, 300, 68, w, h, Graphics.FONT_MEDIUM);
        moreLink(dc, "mehr", w, h);
    }

    // Zweite Seite: was seltener gebraucht wird.
    private function drawMore(dc as Graphics.Dc, s as Dictionary, set as Dictionary, w as Number, h as Number) as Void {
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 100, Graphics.FONT_SMALL, setText(set), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if ("resting".equals(s["status"])) {
            pair(dc, {"id" => "repsMinus", "label" => "- Wdh."}, {"id" => "repsPlus", "label" => "+ Wdh."}, 130, w, h);
        } else {
            var step = kg(set["step"] as Float);
            pair(dc, {"id" => "weightMinus", "label" => "-" + step + " kg"}, {"id" => "weightPlus", "label" => "+" + step + " kg"}, 130, w, h);
        }
        var done = set["doneCount"] as Number;
        var y = 204;
        if (done > 0) {
            button(dc, {"id" => "end", "label" => "Übung beenden (" + done.format("%d") + ")"}, (w - 320) / 2, y, 320, 60, w, h, Graphics.FONT_SMALL);
            y += 68;
        }
        button(dc, {"id" => "undo", "label" => "Zurück"}, (w - 280) / 2, y, 280, 56, w, h, Graphics.FONT_SMALL);
        moreLink(dc, "schließen", w, h);
    }

    // Zwei große Knöpfe nebeneinander.
    private function pair(dc as Graphics.Dc, a as Dictionary, b as Dictionary, y as Number, w as Number, h as Number) as Void {
        var bw = 152;
        var gap = 12;
        var x = (w - 2 * bw - gap) / 2;
        button(dc, a, x, y, bw, 64, w, h, Graphics.FONT_SMALL);
        button(dc, b, x + bw + gap, y, bw, 64, w, h, Graphics.FONT_SMALL);
    }

    // Kleiner Wechsel zwischen Haupt- und Zusatzseite am unteren Rand.
    private function moreLink(dc as Graphics.Dc, label as String, w as Number, h as Number) as Void {
        button(dc, {"id" => page == 0 ? "page1" : "page0", "label" => label}, (w - 130) / 2, 368, 130, 34, w, h, Graphics.FONT_XTINY);
    }

    private function button(dc as Graphics.Dc, b as Dictionary, x as Number, y as Number, bw as Number, bh as Number,
            w as Number, h as Number, font as Graphics.FontType) as Void {
        // Auf dem runden Bildschirm nur so breit, wie es auf dieser Höhe passt.
        var r = w / 2.0;
        var dy = (y + bh > h / 2) ? (y + bh - h / 2.0) : (h / 2.0 - y);
        var maxW = (2 * Math.sqrt(r * r - dy * dy) - 20).toNumber();
        if (bw > maxW) {
            x += (bw - maxW) / 2;
            bw = maxW;
        }
        var id = b["id"] as String;
        var isPrimary = b["p"] == true;
        var lit = pressedId != null && id.equals(pressedId) && System.getTimer() - pressedAt < 400;
        dc.setColor(lit ? PRESSED : (isPrimary ? RED : GREY), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, bw, bh, 16);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + bw / 2, y + bh / 2, font, b["label"] as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        hits.add(new Hit(x, y, bw, bh, id));
        if (isPrimary) {
            primary = id;
        }
    }

    function hitAt(px as Number, py as Number) as String? {
        for (var i = 0; i < hits.size(); i++) {
            var b = hits[i];
            if (px >= b.x && px <= b.x + b.w && py >= b.y && py <= b.y + b.h) {
                return b.id;
            }
        }
        return null;
    }
}
