import Toybox.Lang;
import Toybox.WatchUi;

// Bedienung: Antippen der Knöpfe, obere Taste (START) = roter Hauptknopf,
// untere Taste (ZURÜCK) = letzten Schritt zurücknehmen. Beim Start geht
// ZURÜCK von der Trainingsart zur Ortswahl, dort beendet sie die App.
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
        _app.lastInput = SatzweiseApp.now();
        _view.press(id);
        _app.act(id);
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var id = _view.hitAt(xy[0], xy[1]);
        if (id != null) {
            run(id);
        }
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
            _app.lastInput = SatzweiseApp.now();
            if (_app.phase().equals("idle")) {
                if (_app.pickedPlace != null) {
                    _app.pickedPlace = null;
                    WatchUi.requestUpdate();
                    return true;
                }
                return false;
            }
            run("undo");
            return true;
        }
        return false;
    }
}
