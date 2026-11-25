package de.satzweise.satzweise

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.MethodChannel

/** Was die Benachrichtigung zeigt; kommt als Map aus Flutter. */
data class WorkoutState(
    val title: String,
    val text: String,
    val subText: String,
    /** Basis der laufenden Uhr in Epoch-Millisekunden. */
    val chronoBase: Long,
    /** true = Countdown (Pause), false = läuft hoch (Gesamtzeit). */
    val chronoDown: Boolean,
    /** Ende der laufenden Pause in Epoch-Millisekunden, 0 = keine Pause. */
    val restEndsAt: Long,
    val actions: List<Pair<String, String>>,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>): WorkoutState {
            @Suppress("UNCHECKED_CAST")
            val acts = (m["actions"] as? List<Map<String, Any?>>).orEmpty()
                .map { (it["id"] as String) to (it["label"] as String) }
            return WorkoutState(
                title = m["title"] as? String ?: "",
                text = m["text"] as? String ?: "",
                subText = m["subText"] as? String ?: "",
                chronoBase = (m["chronoBase"] as? Number)?.toLong() ?: 0L,
                chronoDown = m["chronoDown"] as? Boolean ?: false,
                restEndsAt = (m["restEndsAt"] as? Number)?.toLong() ?: 0L,
                actions = acts,
            )
        }
    }
}

/**
 * Leitet Knopfdrücke an Flutter weiter. Läuft die Flutter-Oberfläche gerade
 * nicht, werden sie gesammelt und beim nächsten Start nachgereicht.
 */
object ActionBus {
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<String>()
    private val main = Handler(Looper.getMainLooper())

    fun attach(c: MethodChannel) { channel = c }
    fun detach() { channel = null }

    fun send(action: String) {
        main.post {
            val c = channel
            if (c == null) pending.add(action) else c.invokeMethod("action", action)
        }
    }

    fun drain(): List<String> = pending.toList().also { pending.clear() }
}

class WorkoutActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        intent.getStringExtra(EXTRA_ACTION)?.let { ActionBus.send(it) }
    }

    companion object {
        const val EXTRA_ACTION = "action"
    }
}

/**
 * Vordergrunddienst mit der Trainings-Benachrichtigung. Er hält die App am
 * Laufen, solange trainiert wird, und lässt das Handy am Ende der Pause
 * vibrieren, auch bei gesperrtem Bildschirm.
 */
class WorkoutService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var restEnd = 0L
    private val restDone = Runnable { onRestFinished() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val s = current ?: return START_NOT_STICKY
        val n = build(this, s)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
        scheduleRestEnd(s.restEndsAt)
        return START_NOT_STICKY
    }

    private fun scheduleRestEnd(end: Long) {
        if (end == restEnd) return
        handler.removeCallbacks(restDone)
        restEnd = end
        val delay = end - System.currentTimeMillis()
        if (end > 0 && delay > 0) handler.postDelayed(restDone, delay)
    }

    private fun onRestFinished() {
        restEnd = 0
        vibrate(this)
        ActionBus.send("restFinished")
    }

    override fun onDestroy() {
        handler.removeCallbacks(restDone)
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "workout"
        private const val NOTIFICATION_ID = 42
        private var current: WorkoutState? = null

        fun update(context: Context, s: WorkoutState) {
            current = s
            ensureChannel(context)
            val i = Intent(context, WorkoutService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(i) else context.startService(i)
        }

        fun stop(context: Context) {
            current = null
            context.stopService(Intent(context, WorkoutService::class.java))
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val nm = context.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            val ch = NotificationChannel(CHANNEL_ID, "Laufendes Training", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Satz, Pause und Knöpfe auf dem Sperrbildschirm"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(false)
            }
            nm.createNotificationChannel(ch)
        }

        private fun build(context: Context, s: WorkoutState): Notification {
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL_ID)
            else @Suppress("DEPRECATION") Notification.Builder(context)
            b.setSmallIcon(R.drawable.ic_stat_workout)
                .setContentTitle(s.title)
                .setContentText(s.text)
                .setSubText(s.subText)
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_WORKOUT)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setShowWhen(true)
                .setWhen(s.chronoBase)
                .setUsesChronometer(true)
            if (Build.VERSION.SDK_INT >= 24) b.setChronometerCountDown(s.chronoDown)
            s.actions.take(3).forEachIndexed { i, (id, label) ->
                val pi = PendingIntent.getBroadcast(
                    context, 100 + i,
                    Intent(context, WorkoutActionReceiver::class.java).putExtra(WorkoutActionReceiver.EXTRA_ACTION, id),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                @Suppress("DEPRECATION")
                b.addAction(Notification.Action.Builder(null, label, pi).build())
            }
            if (Build.VERSION.SDK_INT >= 24) b.setStyle(Notification.BigTextStyle().bigText(s.text))
            return b.build()
        }

        private fun vibrate(context: Context) {
            val v = if (Build.VERSION.SDK_INT >= 31) {
                context.getSystemService(VibratorManager::class.java).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            val pattern = longArrayOf(0, 300, 150, 300)
            if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(pattern, -1))
            else @Suppress("DEPRECATION") v.vibrate(pattern, -1)
        }
    }
}
