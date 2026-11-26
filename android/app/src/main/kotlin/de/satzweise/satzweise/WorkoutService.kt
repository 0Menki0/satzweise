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
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.View
import android.widget.RemoteViews
import io.flutter.plugin.common.MethodChannel

/** Ein Textknopf der Benachrichtigung. */
data class LockButton(val id: String, val label: String, val primary: Boolean)

/** Was die Benachrichtigung zeigt; kommt als Map aus Flutter. */
data class WorkoutState(
    val title: String,
    val text: String,
    val dayName: String,
    val startMs: Long,
    /** "setRunning", "resting" oder "none". */
    val status: String,
    val setStartMs: Long,
    val restStartMs: Long,
    val restEndMs: Long,
    val rows: List<List<LockButton>>,
    val wide: LockButton?,
    val sound: Boolean,
) {
    companion object {
        private fun btn(m: Map<String, Any?>?) =
            m?.let { LockButton(it["id"] as String, it["label"] as String, it["primary"] as? Boolean ?: false) }

        fun fromMap(m: Map<String, Any?>): WorkoutState {
            fun l(k: String) = (m[k] as? Number)?.toLong() ?: 0L
            @Suppress("UNCHECKED_CAST")
            val rows = (m["rows"] as? List<List<Map<String, Any?>>>).orEmpty().map { r -> r.mapNotNull { btn(it) } }
            @Suppress("UNCHECKED_CAST")
            return WorkoutState(
                title = m["title"] as? String ?: "",
                text = m["text"] as? String ?: "",
                dayName = m["dayName"] as? String ?: "",
                startMs = l("startMs"),
                status = m["status"] as? String ?: "none",
                setStartMs = l("setStartMs"),
                restStartMs = l("restStartMs"),
                restEndMs = l("restEndMs"),
                rows = rows,
                wide = btn(m["wide"] as? Map<String, Any?>),
                sound = m["sound"] as? Boolean ?: false,
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
 * Vordergrunddienst mit der Trainings-Benachrichtigung: eine normale
 * Benachrichtigung mit eigenem Inhalt, zwei Reihen à drei Textknöpfen und
 * einem breiten Knopf. Er hält die App am Laufen, solange trainiert wird,
 * und meldet das Pausenende mit Vibration und auf Wunsch mit Ton, auch bei
 * gesperrtem Bildschirm.
 */
class WorkoutService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var restEnd = 0L
    private val ticker = object : Runnable {
        override fun run() {
            val s = current ?: return
            val now = System.currentTimeMillis()
            if (restEnd > 0 && now >= restEnd) {
                restEnd = 0
                restFinished(this@WorkoutService, s.sound)
                ActionBus.send("restFinished")
            }
            // Der Pausenbalken läuft nicht von selbst; einmal pro Sekunde nachziehen.
            if (s.status == "resting" && now < s.restEndMs) notifyNow(s)
            handler.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        handler.post(ticker)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        current?.let { render(it) }
        return START_NOT_STICKY
    }

    fun render(s: WorkoutState) {
        restEnd = if (s.status == "resting" && s.restEndMs > System.currentTimeMillis()) s.restEndMs else 0
        val n = build(this, s)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun notifyNow(s: WorkoutState) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, build(this, s))
    }

    override fun onDestroy() {
        handler.removeCallbacks(ticker)
        instance = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "workout"
        private const val NOTIFICATION_ID = 42
        private var current: WorkoutState? = null
        private var instance: WorkoutService? = null

        private val rowIds = listOf(
            listOf(R.id.b1_0, R.id.b1_1, R.id.b1_2),
            listOf(R.id.b2_0, R.id.b2_1, R.id.b2_2),
        )
        private val rowContainers = listOf(R.id.row1, R.id.row2)
        private val smallIds = listOf(R.id.s_0, R.id.s_1, R.id.s_2)

        fun update(context: Context, s: WorkoutState) {
            current = s
            ensureChannel(context)
            val running = instance
            if (running != null) {
                running.render(s)
            } else {
                val i = Intent(context, WorkoutService::class.java)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(i) else context.startService(i)
            }
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

        private fun pending(context: Context, b: LockButton, code: Int): PendingIntent =
            PendingIntent.getBroadcast(
                context, code,
                Intent(context, WorkoutActionReceiver::class.java).putExtra(WorkoutActionReceiver.EXTRA_ACTION, b.id),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        private fun bind(context: Context, v: RemoteViews, id: Int, b: LockButton?, code: Int) {
            if (b == null) {
                v.setViewVisibility(id, View.GONE)
                return
            }
            v.setViewVisibility(id, View.VISIBLE)
            v.setTextViewText(id, b.label)
            v.setOnClickPendingIntent(id, pending(context, b, code))
            if (b.primary) {
                v.setInt(id, "setBackgroundResource", R.drawable.bg_btn_primary)
                v.setTextColor(id, Color.WHITE)
            } else if (id != R.id.wide) {
                v.setInt(id, "setBackgroundResource", R.drawable.bg_btn)
            }
        }

        /** Chronometer-Basis in der Zeitrechnung von SystemClock. */
        private fun base(epochMs: Long) = SystemClock.elapsedRealtime() + (epochMs - System.currentTimeMillis())

        private fun header(context: Context, layout: Int, s: WorkoutState) = RemoteViews(context.packageName, layout).apply {
            setTextViewText(R.id.title, s.title)
            setTextViewText(R.id.text, s.text)
        }

        private fun build(context: Context, s: WorkoutState): Notification {
            val big = header(context, R.layout.notif_workout_big, s)
            when (s.status) {
                "warmup", "setRunning" -> {
                    big.setViewVisibility(R.id.status, View.VISIBLE)
                    big.setTextViewText(R.id.status_label, if (s.status == "warmup") "Aufwärmen" else "Satz läuft")
                    big.setChronometer(R.id.chrono, base(s.setStartMs), null, true)
                    big.setChronometerCountDown(R.id.chrono, false)
                    big.setTextColor(R.id.chrono, Color.parseColor(if (s.status == "warmup") "#1F5FBF" else "#E2322B"))
                    big.setViewVisibility(R.id.progress, View.GONE)
                }
                "resting" -> {
                    big.setViewVisibility(R.id.status, View.VISIBLE)
                    big.setTextViewText(R.id.status_label, "noch")
                    big.setChronometer(R.id.chrono, base(s.restEndMs), null, true)
                    big.setChronometerCountDown(R.id.chrono, true)
                    big.setTextColor(R.id.chrono, Color.parseColor("#1F5FBF"))
                    val total = (s.restEndMs - s.restStartMs).coerceAtLeast(1)
                    val done = (System.currentTimeMillis() - s.restStartMs).coerceIn(0, total)
                    big.setViewVisibility(R.id.progress, View.VISIBLE)
                    big.setProgressBar(R.id.progress, 1000, (done * 1000 / total).toInt(), false)
                }
                else -> {
                    big.setViewVisibility(R.id.status, View.GONE)
                    big.setViewVisibility(R.id.progress, View.GONE)
                }
            }
            var code = 100
            rowIds.forEachIndexed { r, ids ->
                val row = s.rows.getOrNull(r)
                big.setViewVisibility(rowContainers[r], if (row.isNullOrEmpty()) View.GONE else View.VISIBLE)
                ids.forEachIndexed { i, id -> bind(context, big, id, row?.getOrNull(i), code++) }
            }
            bind(context, big, R.id.wide, s.wide, code++)

            val small = header(context, R.layout.notif_workout_small, s)
            val first = s.rows.firstOrNull().orEmpty()
            smallIds.forEachIndexed { i, id -> bind(context, small, id, first.getOrNull(i), code++) }

            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL_ID)
            else @Suppress("DEPRECATION") Notification.Builder(context)
            return builder
                .setSmallIcon(R.drawable.ic_stat_workout)
                .setContentTitle(s.title)
                .setContentText(s.text)
                .setSubText(s.dayName)
                // Laufende Gesamtzeit in der Kopfzeile.
                .setWhen(s.startMs)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_WORKOUT)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setColor(Color.parseColor("#E2322B"))
                .setStyle(Notification.DecoratedCustomViewStyle())
                .setCustomContentView(small)
                .setCustomBigContentView(big)
                .build()
        }

        private fun restFinished(context: Context, sound: Boolean) {
            val v = if (Build.VERSION.SDK_INT >= 31) {
                context.getSystemService(VibratorManager::class.java).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            // Kräftig und als Wecker-Vibration, damit sie auch bei „Nicht
            // stören“ und gesperrtem Bildschirm durchkommt.
            val pattern = longArrayOf(0, 500, 200, 500, 200, 500)
            when {
                Build.VERSION.SDK_INT >= 33 -> v.vibrate(
                    VibrationEffect.createWaveform(pattern, -1),
                    VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM),
                )
                Build.VERSION.SDK_INT >= 26 -> @Suppress("DEPRECATION") v.vibrate(
                    VibrationEffect.createWaveform(pattern, -1),
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build(),
                )
                else -> @Suppress("DEPRECATION") v.vibrate(pattern, -1)
            }
            if (sound) {
                // Benachrichtigungston des Handys; bleibt stumm, wenn das Handy stumm ist.
                runCatching {
                    RingtoneManager.getRingtone(context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))?.apply {
                        audioAttributes = AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                        play()
                    }
                }
            }
        }
    }
}
