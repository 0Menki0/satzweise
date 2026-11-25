package de.satzweise.satzweise

import android.content.Context
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
 * wiederholt). Uhr → Flutter: "action" mit der ID des gedrückten Knopfs,
 * "hello", wenn die Uhren-App startet.
 */
object WatchBridge {
    private const val TAG = "SatzweiseWatch"

    /** Muss zur id in watch/manifest.xml passen. */
    private const val APP_ID = "90448ca7b7b94e50b6a40868819436e5"

    private var ciq: ConnectIQ? = null
    private var ready = false
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<String>()
    private var last: Map<String, Any?>? = null
    private val app = IQApp(APP_ID)
    private val main = Handler(Looper.getMainLooper())

    fun attach(context: Context, c: MethodChannel) {
        channel = c
        if (ciq != null) return
        val inst = ConnectIQ.getInstance(context.applicationContext, ConnectIQ.IQConnectType.WIRELESS)
        ciq = inst
        inst.initialize(context.applicationContext, false, object : ConnectIQ.ConnectIQListener {
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
                inst.registerForDeviceEvents(d) { device, status ->
                    if (status == IQDevice.IQDeviceStatus.CONNECTED) last?.let { send(it) }
                }
                inst.registerForAppEvents(d, app) { _, _, message, _ ->
                    for (m in message) {
                        val action = (m as? Map<*, *>)?.get("a") as? String ?: continue
                        deliver(action)
                    }
                }
            }.onFailure { Log.w(TAG, "Anmelden bei ${d.friendlyName} fehlgeschlagen", it) }
        }
    }

    private fun deliver(action: String) {
        main.post {
            val c = channel
            if (c == null) pending.add(action) else c.invokeMethod("action", action)
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
