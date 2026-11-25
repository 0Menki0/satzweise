import Toybox.Lang;
import Toybox.WatchUi;

// Bedienung: Antippen der Knöpfe, obere Taste (START) = Hauptaktion,
// untere Taste (ZURÜCK) = letzten Schritt zurücknehmen. Ohne laufendes
// Training beendet ZURÜCK die App wie gewohnt.
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

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var id = _view.hitAt(xy[0], xy[1]);
        if (id != null) {
            _app.act(id);
        }
        return true;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ENTER) {
            var id = _view.primary;
            if (id != null) {
                _app.act(id);
            }
            return true;
        }
        if (key == WatchUi.KEY_ESC) {
            var s = _app.state;
            if (s == null || s["idle"] == true) {
                return false;
            }
            _app.act("undo");
            return true;
        }
        return false;
    }
}
