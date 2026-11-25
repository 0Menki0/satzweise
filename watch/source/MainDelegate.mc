import Toybox.Lang;
import Toybox.WatchUi;

// Bedienung: Antippen der Knöpfe, obere Taste (START) = Hauptaktion,
// untere Taste (ZURÜCK) = letzten Schritt zurücknehmen bzw. von der
// Zusatzseite zurück. Wischen nach oben/unten wechselt zur Zusatzseite.
// Ohne laufendes Training beendet ZURÜCK die App wie gewohnt.
//
// Bewusst ein InputDelegate und kein BehaviorDelegate: Dieser macht aus
// jedem Antippen ein „Select“ ohne Position, dann löst jeder Tipp die
// Hauptaktion aus.
class MainDelegate extends WatchUi.InputDelegate {
    private var _app as SatzweiseApp;
    private var _view as MainView;

    function initialize(app as SatzweiseApp, view as MainView) {
        InputDelegate.initialize();
        _app = app;
        _view = view;
    }

    private function run(id as String) as Void {
        _view.press(id);
        if (id.equals("page1")) {
            _view.page = 1;
            WatchUi.requestUpdate();
        } else if (id.equals("page0")) {
            _view.page = 0;
            WatchUi.requestUpdate();
        } else {
            _app.act(id);
        }
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var id = _view.hitAt(xy[0], xy[1]);
        if (id != null) {
            run(id);
        }
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var d = evt.getDirection();
        var s = _app.state;
        var inSet = s != null && s["set"] != null && ("setRunning".equals(s["status"]) || "resting".equals(s["status"]));
        if (!inSet) {
            return true;
        }
        if (d == WatchUi.SWIPE_UP) {
            _view.page = 1;
        } else if (d == WatchUi.SWIPE_DOWN) {
            _view.page = 0;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ENTER) {
            var id = _view.primary;
            if (id != null) {
                run(id);
            }
            return true;
        }
        if (key == WatchUi.KEY_ESC) {
            if (_view.page == 1) {
                _view.page = 0;
                WatchUi.requestUpdate();
                return true;
            }
            var s = _app.state;
            if (s == null || s["idle"] == true) {
                return false;
            }
            run("undo");
            return true;
        }
        return false;
    }
}
