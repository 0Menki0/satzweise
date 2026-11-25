import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
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

class MainView extends WatchUi.View {
    const RED = 0xE2322B;
    const BLUE = 0x5B93EA;
    const GREEN = 0x1D8A4D;
    const GREY = 0x2A2A2C;
    const MUTE = 0xA0A0A8;

    private var _app as SatzweiseApp;
    var hits as Array<Hit> = [] as Array<Hit>;
    var primary as String? = null;

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
            // Nullen am Ende weg, Komma statt Punkt.
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

    // Knöpfe für Satz und Pause baut die Uhr selbst, damit sie ohne
    // Verbindung bedienbar bleibt; die übrigen Schritte kommen vom Handy.
    static function localRows(s as Dictionary) as Array {
        var set = s["set"] as Dictionary;
        var step = kg(set["step"] as Float);
        if ("resting".equals(s["status"])) {
            return [
                [{"id" => "restMinus", "label" => "−15 s"}, {"id" => "restPlus", "label" => "+15 s"}, {"id" => "skip", "label" => "Weiter", "p" => true}],
                [{"id" => "repsMinus", "label" => "− Wdh."}, {"id" => "repsPlus", "label" => "+ Wdh."}, {"id" => "end", "label" => "Ende"}]
            ];
        }
        var row2 = [{"id" => "weightMinus", "label" => "−" + step}, {"id" => "weightPlus", "label" => "+" + step}];
        if ((set["doneCount"] as Number) > 0) {
            row2.add({"id" => "end", "label" => "Ende"});
        }
        return [
            [{"id" => "repsMinus", "label" => "− Wdh."}, {"id" => "repsPlus", "label" => "+ Wdh."}, {"id" => "done", "label" => "Fertig", "p" => true}],
            row2
        ];
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
            dc.drawText(cx, h * 0.55, Graphics.FONT_XTINY, "Öffne Satzweise\nauf dem Handy", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var now = SatzweiseApp.now();
        var status = s["status"];
        var idle = s["idle"] == true;

        // Kopf: Tag, Gesamtzeit, Puls, Verbindung.
        var head = s["day"] != null ? s["day"] as String : "Satzweise";
        if (!idle && s["startS"] != null) {
            head = head + " · " + clock(now - (s["startS"] as Number));
        }
        dc.setColor(MUTE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 36, Graphics.FONT_XTINY, head, Graphics.TEXT_JUSTIFY_CENTER);
        var hr = _app.heartRate();
        var line2 = (hr != null ? "♥ " + hr.format("%d") : "");
        if (_app.queue.size() > 0 && !_app.connected) {
            line2 = line2 + (line2.length() > 0 ? " · " : "") + "offline (" + _app.queue.size().format("%d") + ")";
        }
        if (line2.length() > 0) {
            dc.setColor(RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 64, Graphics.FONT_XTINY, line2, Graphics.TEXT_JUSTIFY_CENTER);
        }

        var rows = s["rows"] as Array?;
        var wide = s["wide"] as Dictionary?;
        var set = s["set"] as Dictionary?;

        if (set != null && "setRunning".equals(status)) {
            rows = localRows(s);
            wide = null;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 104, Graphics.FONT_SMALL, set["ex"] as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            var info = "Satz " + (set["no"] as Number).format("%d");
            if (s["setStartS"] != null) {
                info = info + " · " + clock(now - (s["setStartS"] as Number));
            }
            dc.setColor(now - _app.restFinishedAt < 5 ? GREEN : MUTE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 138, Graphics.FONT_XTINY, now - _app.restFinishedAt < 5 ? "Pause vorbei · los!" : info, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(0xFF6A62, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 190, Graphics.FONT_LARGE, setText(set), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (set != null && "resting".equals(status)) {
            rows = localRows(s);
            wide = null;
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
            dc.drawText(cx, 104, Graphics.FONT_XTINY, "Pause · danach Satz " + (set["no"] as Number).format("%d"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 165, Graphics.FONT_NUMBER_HOT, clock(left), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 222, Graphics.FONT_XTINY, setText(set), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 120, Graphics.FONT_SMALL, s["title"] as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (s["text"] != null) {
                dc.setColor(MUTE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, 165, Graphics.FONT_XTINY, s["text"] as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            if (_app.queue.size() > 0 && !_app.connected) {
                dc.setColor(RED, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, 205, Graphics.FONT_XTINY, "wird übernommen, sobald\ndas Handy erreichbar ist", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }

        // Knöpfe: zwei Reihen à drei, darunter ein breiter.
        var y = 252;
        if (rows != null) {
            for (var r = 0; r < rows.size() && r < 2; r++) {
                drawRow(dc, rows[r] as Array, y, 50, w, h);
                y += 58;
            }
        }
        if (wide != null) {
            drawRow(dc, [wide] as Array, y, 42, w, h);
        }
    }

    // Breite, die der runde Bildschirm auf Höhe y bietet.
    private function chord(y as Number, bh as Number, w as Number, h as Number) as Number {
        var r = w / 2.0;
        var dy = (y + bh > h / 2) ? (y + bh - h / 2.0) : (h / 2.0 - y);
        var half = Math.sqrt(r * r - dy * dy);
        return (2 * half - 16).toNumber();
    }

    private function drawRow(dc as Graphics.Dc, row as Array, y as Number, bh as Number, w as Number, h as Number) as Void {
        var n = row.size();
        if (n == 0) {
            return;
        }
        var avail = chord(y, bh, w, h);
        if (avail > 330) {
            avail = 330;
        }
        var gap = 8;
        var bw = (avail - gap * (n - 1)) / n;
        var x = (w - avail) / 2;
        for (var i = 0; i < n; i++) {
            var b = row[i] as Dictionary;
            var isPrimary = b["p"] == true;
            dc.setColor(isPrimary ? RED : GREY, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, bw, bh, 14);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + bw / 2, y + bh / 2, Graphics.FONT_XTINY, b["label"] as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            var id = b["id"] as String;
            hits.add(new Hit(x, y, bw, bh, id));
            if (isPrimary) {
                primary = id;
            }
            x += bw + gap;
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
