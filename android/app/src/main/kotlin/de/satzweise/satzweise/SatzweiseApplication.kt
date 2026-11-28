package de.satzweise.satzweise

import android.app.Application

/**
 * Startet die Verbindung zur Uhr schon mit dem Prozess. Garmin Connect
 * weckt Satzweise für eine Nachricht von der Uhr auch dann auf, wenn die
 * App geschlossen ist – dann gibt es noch keine Activity, die zuhört.
 */
class SatzweiseApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        WatchBridge.init(this)
    }
}
