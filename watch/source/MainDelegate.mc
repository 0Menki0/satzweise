import Toybox.Lang;
import Toybox.WatchUi;

// Bedienung: Antippen der Knöpfe, obere Taste (START) = Hauptaktion,
// untere Taste (ZURÜCK) = letzten Schritt zurücknehmen. Ohne laufendes
// Training beendet ZURÜCK die App wie gewohnt.
class MainDelegate extends WatchUi.BehaviorDelegate {
    private var _app as SatzweiseApp;
    private var _view as MainView;

    function initialize(app as SatzweiseApp, view as MainView) {
        BehaviorDelegate.initialize();
        _app = app;
        _view = view;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var id = _view.hitAt(xy[0], xy[1]);
        if (id != null) {
            _app.act(id);
        }
        // Immer behandelt, damit ein Tipp daneben nicht als START zählt.
        return true;
    }

    function onSelect() as Boolean {
        var id = _view.primary;
        if (id != null) {
            _app.act(id);
        }
        return true;
    }

    function onBack() as Boolean {
        var s = _app.state;
        if (s == null || s["idle"] == true) {
            return false;
        }
        _app.act("undo");
        return true;
    }
}
