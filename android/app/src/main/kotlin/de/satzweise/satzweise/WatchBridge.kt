package de.satzweise.satzweise

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import io.flutter.plugin.common.MethodChannel

/**
 * Verbindung zur Satzweise-App auf der Garmin-Uhr über Garmin Connect.
 *
 * Flutter → Uhr: [send] mit dem aktuellen Stand (wird bei neuer Verbindung
 * wiederholt), [open] öffnet die App auf der Uhr. Uhr → Flutter: "action"
 * mit der ID des gedrückten Knopfs, "hello", wenn die Uhren-App startet.
 *
 * Läuft die Handy-App nicht, wenn auf der Uhr ein Training beginnt, merkt
 * sich die Brücke den Knopfdruck und zeigt eine Benachrichtigung, die
 * Satzweise öffnet; dann wird das Training gestartet.
 */
object WatchBridge {
    private const val TAG = "SatzweiseWatch"

    /** Muss zur id in watch/manifest.xml passen. */
    private const val APP_ID = "90448ca7b7b94e50b6a40868819436e5"
    private const val WAKE_CHANNEL = "watch"
    private const val WAKE_ID = 2

    /** Älter als das: nicht mehr ausführen (z. B. lange offline gesammelt). */
    private const val STALE_SEC = 15 * 60

    private var ciq: ConnectIQ? = null
    private var ready = false
    private var appContext: Context? = null
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<String>()
    private var last: Map<String, Any?>? = null
    private val app = IQApp(APP_ID)
    private val main = Handler(Looper.getMainLooper())

    /** Schon gesehene Knopfdrücke („Sitzung:Nummer“), damit doppelt
     *  zugestellte Nachrichten keine doppelten Sätze anlegen. */
    private val seen = LinkedHashSet<String>()

    fun init(context: Context) {
        if (ciq != null) return
        val ctx = context.applicationContext
        appContext = ctx
        val inst = runCatching { ConnectIQ.getInstance(ctx, ConnectIQ.IQConnectType.WIRELESS) }.getOrNull() ?: return
        ciq = inst
        runCatching {
            inst.initialize(ctx, false, object : ConnectIQ.ConnectIQListener {
                override fun onSdkReady() {
                    ready = true
                    register()
                    last?.let { send(it) }
                }

                override fun onInitializeError(status: ConnectIQ.IQSdkErrorStatus) {
                    // Garmin Connect fehlt oder ist zu alt: ohne Uhr weiter.
                    Log.i(TAG, "Connect IQ nicht verfügbar: $status")
                }

                override fun onSdkShutDown() {
                    ready = false
                }
            })
        }.onFailure { Log.w(TAG, "Connect IQ starten fehlgeschlagen", it) }
    }

    fun attach(context: Context, c: MethodChannel) {
        channel = c
        init(context)
        // Die App ist offen: der Hinweis „Satzweise öffnen“ hat sich erledigt.
        context.getSystemService(NotificationManager::class.java)?.cancel(WAKE_ID)
    }

    fun detach() {
        channel = null
    }

    fun drain(): List<String> = pending.toList().also { pending.clear() }

    private fun register() {
        val inst = ciq ?: return
        val devices = runCatching { inst.knownDevices }.getOrNull().orEmpty()
        for (d in devices) {
            runCatching {
                inst.registerForDeviceEvents(d) { _, status ->
                    if (status == IQDevice.IQDeviceStatus.CONNECTED) last?.let { send(it) }
                }
                inst.registerForAppEvents(d, app) { _, _, message, _ ->
                    for (m in message) {
                        val map = m as? Map<*, *> ?: continue
                        val action = map["a"] as? String ?: continue
                        if (accept(map, action)) deliver(action)
                    }
                }
            }.onFailure { Log.w(TAG, "Anmelden bei ${d.friendlyName} fehlgeschlagen", it) }
        }
    }

    private fun num(v: Any?): Long? = (v as? Number)?.toLong()

    /** Doppelte und veraltete Knopfdrücke aussortieren. */
    private fun accept(m: Map<*, *>, action: String): Boolean {
        if (action == "hello") return true
        val sid = num(m["sid"])
        val n = num(m["n"])
        if (sid != null && n != null) {
            val key = "$sid:$n"
            if (!seen.add(key)) {
                Log.i(TAG, "Doppelt von der Uhr, ignoriert: $action ($key)")
                return false
            }
            while (seen.size > 500) seen.remove(seen.first())
        }
        val ts = num(m["ts"])
        if (ts != null && System.currentTimeMillis() / 1000 - ts > STALE_SEC) {
            Log.i(TAG, "Veraltet von der Uhr, ignoriert: $action")
            return false
        }
        return true
    }

    private fun deliver(action: String) {
        main.post {
            val c = channel
            if (c != null) {
                c.invokeMethod("action", action)
                return@post
            }
            if (action == "hello") return@post
            pending.add(action)
            if (action.startsWith("go:")) askToOpen()
        }
    }

    /** Training auf der Uhr gestartet, Handy-App zu: Hinweis zum Öffnen.
     *  (Android lässt Apps aus dem Hintergrund nicht selbst nach vorne.) */
    private fun askToOpen() {
        val ctx = appContext ?: return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(WAKE_CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(WAKE_CHANNEL, "Start von der Uhr", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Wenn auf der Uhr ein Training beginnt und Satzweise zu ist"
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            )
        }
        val open = PendingIntent.getActivity(
            ctx, 0,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, WAKE_CHANNEL) else Notification.Builder(ctx)
        val n = b.setSmallIcon(R.drawable.ic_stat_workout)
            .setContentTitle("Training auf der Uhr gestartet")
            .setContentText("Tippen, um Satzweise auf dem Handy zu öffnen")
            .setContentIntent(open)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_WORKOUT)
            .build()
        runCatching { nm.notify(WAKE_ID, n) }.onFailure { Log.w(TAG, "Hinweis nicht möglich", it) }
    }

    /** Öffnet Satzweise auf den verbundenen Uhren (die Uhr fragt nach). */
    fun open() {
        val inst = ciq ?: return
        if (!ready) return
        val devices = runCatching { inst.connectedDevices }.getOrNull().orEmpty()
        for (d in devices) {
            runCatching {
                inst.openApplication(d, app) { _, _, status -> Log.i(TAG, "Uhr öffnen: $status") }
            }.onFailure { Log.w(TAG, "Uhr öffnen fehlgeschlagen", it) }
        }
    }

    /** Schickt den Stand an alle verbundenen Uhren. */
    fun send(state: Map<String, Any?>) {
        last = state
        val inst = ciq ?: return
        if (!ready) return
        val devices = runCatching { inst.connectedDevices }.getOrNull().orEmpty()
        for (d in devices) {
            runCatching {
                inst.sendMessage(d, app, state) { _, _, status ->
                    if (status != ConnectIQ.IQMessageStatus.SUCCESS) Log.i(TAG, "Senden an Uhr: $status")
                }
            }
        }
    }
}
