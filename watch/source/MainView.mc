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

// Ein Bildschirm je Schritt, jeweils mit einer großen roten Hauptaktion
// (auch obere Taste). Untere Taste = Zurück.
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
            text(dc, cx, h * 0.4, Graphics.FONT_MEDIUM, "Satzweise", Graphics.COLOR_WHITE);
            text(dc, cx, h * 0.56, Graphics.FONT_TINY, "Öffne Satzweise\nauf dem Handy", MUTE);
            return;
        }
        var now = SatzweiseApp.now();
        var p = _app.phase();

        // Kopf: Tag, Gesamtzeit; darunter Senden, offline oder Puls.
        var head = s["day"] != null ? s["day"] as String : "Satzweise";
        if (!p.equals("idle") && s["startS"] != null) {
            var timed = p.equals("warmup") || p.equals("set") || p.equals("log") || p.equals("rest");
            var total = now - (s["startS"] as Number);
            // Ohne laufende Uhr nur Minuten: dann muss nicht jede Sekunde
            // neu gezeichnet werden.
            head = head + " · " + (timed ? clock(total) : (total / 60).format("%d") + " min");
        }
        dc.setColor(MUTE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 34, Graphics.FONT_XTINY, head, Graphics.TEXT_JUSTIFY_CENTER);
        var line2 = "";
        if (_app.sending) {
            line2 = "sendet …";
        } else if (_app.queue.size() > 0 && !_app.connected) {
            line2 = "offline, " + _app.queue.size().format("%d") + " offen";
        } else if (!p.equals("idle")) {
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
        if (p.equals("idle")) {
            drawStart(dc, s, w, h);
        } else if (set != null && p.equals("warmup")) {
            drawWarmup(dc, s, set, now, w, h);
        } else if (set != null && p.equals("set")) {
            drawSet(dc, s, set, now, w, h);
        } else if (set != null && p.equals("log")) {
            drawLog(dc, s, set, now, w, h);
        } else if (set != null && p.equals("rest")) {
            drawRest(dc, s, set, now, w, h);
        } else {
            drawList(dc, s, w, h);
        }
    }

    private function text(dc as Graphics.Dc, x as Numeric, y as Numeric, font as Graphics.FontType, t as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, t, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // 1 Ort, 2 Trainingsart.
    private function drawStart(dc as Graphics.Dc, s as Dictionary, w as Number, h as Number) as Void {
        var cx = w / 2;
        if (_app.ended != null) {
            text(dc, cx, h * 0.45, Graphics.FONT_MEDIUM, _app.ended.equals("saved") ? "Gespeichert" : "Verworfen", Graphics.COLOR_WHITE);
            text(dc, cx, h * 0.58, Graphics.FONT_XTINY, "Satzweise schließt sich", MUTE);
            return;
        }
        if (_app.queue.size() > 0) {
            text(dc, cx, h * 0.42, Graphics.FONT_SMALL, "Warte auf das Handy", Graphics.COLOR_WHITE);
            text(dc, cx, h * 0.56, Graphics.FONT_XTINY, "Öffne Satzweise\nauf dem Handy", MUTE);
            return;
        }
        var picked = _app.pickedPlace;
        if (picked == null) {
            text(dc, cx, 112, Graphics.FONT_SMALL, "Wo trainierst du?", Graphics.COLOR_WHITE);
            var usual = s["place"] != null ? s["place"] as String : "studio";
            var studio = {"id" => "place:studio", "label" => "Studio", "p" => usual.equals("studio")};
            var home = {"id" => "place:home", "label" => "Daheim", "p" => usual.equals("home")};
            button(dc, studio, (w - 300) / 2, 160, 300, 66, w, h, Graphics.FONT_MEDIUM);
            button(dc, home, (w - 300) / 2, 238, 300, 66, w, h, Graphics.FONT_MEDIUM);
            return;
        }
        text(dc, cx, 100, Graphics.FONT_XTINY, picked.equals("home") ? "Daheim" : "Studio", MUTE);
        text(dc, cx, 128, Graphics.FONT_SMALL, "Was trainierst du?", Graphics.COLOR_WHITE);
        var days = s["days"] as Array?;
        if (days == null) {
            return;
        }
        var y = 160;
        for (var i = 0; i < days.size() && i < 3; i++) {
            var d = days[i] as Dictionary;
            button(dc, {"id" => "go:" + (d["id"] as String) + ":" + picked, "label" => d["label"], "p" => d["p"] == true},
                (w - 300) / 2, y, 300, 60, w, h, Graphics.FONT_SMALL);
            y += 68;
        }
    }

    // 4 Aufwärmen: Zeit läuft, geplanter erster Satz, „Satz starten“.
    private function drawWarmup(dc as Graphics.Dc, s as Dictionary, set as Dictionary, now as Number, w as Number, h as Number) as Void {
        var cx = w / 2;
        text(dc, cx, 102, Graphics.FONT_SMALL, set["ex"] as String, Graphics.COLOR_WHITE);
        text(dc, cx, 132, Graphics.FONT_XTINY, "Aufwärmen", MUTE);
        var start = s["warmupS"] != null ? s["warmupS"] as Number : now;
        text(dc, cx, 178, Graphics.FONT_NUMBER_MEDIUM, clock(now - start), BLUE);
        text(dc, cx, 232, Graphics.FONT_XTINY, "1. Satz: " + setText(set), Graphics.COLOR_WHITE);
        button(dc, {"id" => "startSet", "label" => "Satz starten", "p" => true}, (w - 300) / 2, 268, 300, 72, w, h, Graphics.FONT_MEDIUM);
    }

    // 5 Satz läuft: Übung, Zeit, Puls (oben), „Satz beenden“.
    private function drawSet(dc as Graphics.Dc, s as Dictionary, set as Dictionary, now as Number, w as Number, h as Number) as Void {
        var cx = w / 2;
        text(dc, cx, 106, Graphics.FONT_SMALL, (set["ex"] as String) + " · Satz " + (set["no"] as Number).format("%d"), Graphics.COLOR_WHITE);
        var fresh = now - _app.restFinishedAt < 5;
        text(dc, cx, 138, Graphics.FONT_XTINY, fresh ? "Pause vorbei · los!" : "geplant " + setText(set), fresh ? GREEN : MUTE);
        var start = s["setStartS"] != null ? s["setStartS"] as Number : now;
        text(dc, cx, 196, Graphics.FONT_NUMBER_HOT, clock(now - start), 0xFF6A62);
        button(dc, {"id" => "done", "label" => "Satz beenden", "p" => true}, (w - 300) / 2, 268, 300, 72, w, h, Graphics.FONT_MEDIUM);
    }

    // Ring am Rand: Pause läuft rückwärts.
    private function ring(dc as Graphics.Dc, s as Dictionary, now as Number, w as Number, h as Number) as Number {
        var cx = w / 2;
        var end = s["restEndS"] as Number;
        if (end <= 0) {
            return 0;
        }
        var start = s["restStartS"] as Number;
        var total = end - start;
        var left = end - now;
        if (total > 0) {
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
        return left;
    }

    // 6 Pause beginnt: Satz eintragen, „Weiter“ oder „Übung beenden“.
    private function drawLog(dc as Graphics.Dc, s as Dictionary, set as Dictionary, now as Number, w as Number, h as Number) as Void {
        var cx = w / 2;
        var left = ring(dc, s, now, w, h);
        text(dc, cx, 100, Graphics.FONT_XTINY, "Pause " + clock(left), BLUE);
        text(dc, cx, 126, Graphics.FONT_SMALL, "Wie lief Satz " + (set["no"] as Number).format("%d") + "?", Graphics.COLOR_WHITE);
        stepper(dc, "repsMinus", "repsPlus", (set["reps"] as Number).format("%d") + " Wdh.", 150, w, h);
        var wl = set["bw"] == true && (set["w"] as Float) == 0 ? "KG" : kg(set["w"] as Float) + " kg";
        stepper(dc, "weightMinus", "weightPlus", wl, 206, w, h);
        button(dc, {"id" => "cont", "label" => "Weiter", "p" => true}, (w - 260) / 2, 264, 260, 56, w, h, Graphics.FONT_MEDIUM);
        button(dc, {"id" => "end", "label" => "Übung beenden"}, (w - 200) / 2, 328, 200, 42, w, h, Graphics.FONT_XTINY);
    }

    // 7 Pause: nachkorrigieren oder beenden.
    private function drawRest(dc as Graphics.Dc, s as Dictionary, set as Dictionary, now as Number, w as Number, h as Number) as Void {
        var cx = w / 2;
        var left = ring(dc, s, now, w, h);
        text(dc, cx, 102, Graphics.FONT_XTINY, "danach Satz " + (set["no"] as Number).format("%d") + " · " + setText(set), MUTE);
        text(dc, cx, 158, Graphics.FONT_NUMBER_HOT, clock(left), BLUE);
        var bw = 140;
        var gap = 12;
        var x = (w - 2 * bw - gap) / 2;
        button(dc, {"id" => "restMinus", "label" => "-15 s"}, x, 210, bw, 56, w, h, Graphics.FONT_SMALL);
        button(dc, {"id" => "restPlus", "label" => "+15 s"}, x + bw + gap, 210, bw, 56, w, h, Graphics.FONT_SMALL);
        button(dc, {"id" => "skip", "label" => "Pause beenden", "p" => true}, (w - 290) / 2, 276, 290, 64, w, h, Graphics.FONT_SMALL);
    }

    // Übung wählen, Rückmeldung, Abschluss: Knöpfe untereinander.
    private function drawList(dc as Graphics.Dc, s as Dictionary, w as Number, h as Number) as Void {
        var cx = w / 2;
        text(dc, cx, 104, Graphics.FONT_SMALL, s["title"] != null ? s["title"] as String : "", Graphics.COLOR_WHITE);
        if (s["text"] != null && (s["text"] as String).length() > 0) {
            text(dc, cx, 134, Graphics.FONT_XTINY, s["text"] as String, MUTE);
        }
        var list = [] as Array<Dictionary>;
        var rows = s["rows"] as Array?;
        if (rows != null) {
            for (var r = 0; r < rows.size(); r++) {
                var row = rows[r] as Array;
                for (var i = 0; i < row.size(); i++) {
                    var b = row[i] as Dictionary;
                    // „Zurück“ liegt auf der unteren Taste.
                    if (!"undo".equals(b["id"])) {
                        list.add(b);
                    }
                }
            }
        }
        var wide = s["wide"] as Dictionary?;
        var n = list.size() > 3 ? 3 : list.size();
        var y = 160;
        for (var i = 0; i < n; i++) {
            var long = (list[i]["label"] as String).length() > 15;
            button(dc, list[i], (w - 300) / 2, y, 300, 56, w, h, long ? Graphics.FONT_TINY : Graphics.FONT_SMALL);
            y += 62;
        }
        if (wide != null && !"undo".equals(wide["id"])) {
            button(dc, wide, (w - 210) / 2, y + 2, 210, 40, w, h, Graphics.FONT_XTINY);
        }
    }

    // Wert mit großem − und + links und rechts.
    private function stepper(dc as Graphics.Dc, minus as String, plus as String, label as String, y as Number, w as Number, h as Number) as Void {
        var bw = 70;
        var x0 = (w - 300) / 2;
        button(dc, {"id" => minus, "label" => "-"}, x0, y, bw, 50, w, h, Graphics.FONT_MEDIUM);
        button(dc, {"id" => plus, "label" => "+"}, x0 + 300 - bw, y, bw, 50, w, h, Graphics.FONT_MEDIUM);
        text(dc, w / 2, y + 25, Graphics.FONT_SMALL, label, Graphics.COLOR_WHITE);
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
