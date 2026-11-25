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
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.MethodChannel

/** Ein Knopf; [icon] ist der Name eines Symbols (siehe [iconRes]). */
data class LockButton(val id: String, val label: String, val icon: String)

/** Was der Sperrbildschirm zeigt; kommt als Map aus Flutter. */
data class WorkoutState(
    val title: String,
    /** Zweite Zeile. „{total}“ wird durch die laufende Gesamtzeit ersetzt. */
    val subtitle: String,
    val dayName: String,
    /** "set" = Satz läuft, "rest" = Pause, "other" = Rückmeldung usw. */
    val mode: String,
    val startMs: Long,
    val setStartMs: Long,
    val restStartMs: Long,
    val restEndMs: Long,
    /** Hauptaktion auf dem großen Knopf (⏸ im Satz, ▶ in der Pause). */
    val primary: LockButton?,
    val buttons: List<LockButton>,
    val artKey: String,
) {
    companion object {
        private fun btn(m: Map<String, Any?>?) =
            m?.let { LockButton(it["id"] as String, it["label"] as String, it["icon"] as? String ?: "") }

        fun fromMap(m: Map<String, Any?>): WorkoutState {
            @Suppress("UNCHECKED_CAST")
            val list = (m["buttons"] as? List<Map<String, Any?>>).orEmpty().mapNotNull { btn(it) }
            fun l(k: String) = (m[k] as? Number)?.toLong() ?: 0L
            @Suppress("UNCHECKED_CAST")
            return WorkoutState(
                title = m["title"] as? String ?: "",
                subtitle = m["subtitle"] as? String ?: "",
                dayName = m["dayName"] as? String ?: "",
                mode = m["mode"] as? String ?: "other",
                startMs = l("startMs"),
                setStartMs = l("setStartMs"),
                restStartMs = l("restStartMs"),
                restEndMs = l("restEndMs"),
                primary = btn(m["primary"] as? Map<String, Any?>),
                buttons = list,
                artKey = m["artKey"] as? String ?: "",
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

/** Knöpfe der Benachrichtigung auf Android 12 und älter. */
class WorkoutActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        intent.getStringExtra(EXTRA_ACTION)?.let { ActionBus.send(it) }
    }

    companion object {
        const val EXTRA_ACTION = "action"
    }
}

/**
 * Vordergrunddienst, der das Training wie einen Musikplayer auf dem
 * Sperrbildschirm zeigt: Piktogramm als Bild, Übung als Titel, Pause als
 * Fortschrittsbalken und bis zu fünf Knöpfe. Am Ende der Pause vibriert er,
 * auch bei gesperrtem Bildschirm.
 */
class WorkoutService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var session: MediaSession? = null
    private var restEnd = 0L
    private var lastMinute = -1L
    private val ticker = object : Runnable {
        override fun run() {
            val s = current ?: return
            val now = System.currentTimeMillis()
            if (restEnd > 0 && now >= restEnd) {
                restEnd = 0
                vibrate(this@WorkoutService)
                ActionBus.send("restFinished")
            }
            if (s.mode == "rest") applyPlayback(s)
            val minute = (now - s.startMs) / 60000
            if (minute != lastMinute) {
                lastMinute = minute
                applyMetadata(s)
            }
            handler.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        session = MediaSession(this, "Satzweise").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() { current?.primary?.let { ActionBus.send(it.id) } }
                override fun onPause() { current?.primary?.let { ActionBus.send(it.id) } }
                override fun onCustomAction(action: String, extras: Bundle?) { ActionBus.send(action) }
            })
            isActive = true
        }
        handler.post(ticker)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val s = current ?: return START_NOT_STICKY
        render(s)
        return START_NOT_STICKY
    }

    fun render(s: WorkoutState) {
        restEnd = if (s.mode == "rest" && s.restEndMs > System.currentTimeMillis()) s.restEndMs else 0
        lastMinute = (System.currentTimeMillis() - s.startMs) / 60000
        applyMetadata(s)
        applyPlayback(s)
        val n = build(s)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun subtitle(s: WorkoutState): String {
        val min = ((System.currentTimeMillis() - s.startMs) / 60000).coerceAtLeast(0)
        return s.subtitle.replace("{total}", "Gesamt $min min")
    }

    private fun applyMetadata(s: WorkoutState) {
        val (duration, _) = progress(s)
        val b = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, s.title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, subtitle(s))
            .putString(MediaMetadata.METADATA_KEY_ALBUM, s.dayName)
            .putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
        artwork?.let { b.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, it) }
        session?.setMetadata(b.build())
        if (Build.VERSION.SDK_INT < 33) {
            // Ältere Android-Versionen lesen den Text aus der Benachrichtigung.
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, build(s))
        }
    }

    /** Dauer und Position des Balkens: Pause als Countdown, Satz als laufende Zeit. */
    private fun progress(s: WorkoutState): Pair<Long, Long> {
        val now = System.currentTimeMillis()
        return when (s.mode) {
            "rest" -> (s.restEndMs - s.restStartMs).coerceAtLeast(1000) to (now - s.restStartMs).coerceIn(0, s.restEndMs - s.restStartMs)
            "set" -> {
                val pos = (now - s.setStartMs).coerceAtLeast(0)
                maxOf(120_000L, pos + 30_000L) to pos
            }
            else -> 0L to 0L
        }
    }

    private fun applyPlayback(s: WorkoutState) {
        val (_, pos) = progress(s)
        var actions = 0L
        if (s.primary != null) {
            actions = actions or PlaybackState.ACTION_PLAY_PAUSE or
                if (s.mode == "set") PlaybackState.ACTION_PAUSE else PlaybackState.ACTION_PLAY
        }
        val st = PlaybackState.Builder()
            .setActions(actions)
            .setState(
                if (s.mode == "set") PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                pos,
                if (s.mode == "set") 1f else 0f,
            )
        s.buttons.take(4).forEach { b ->
            st.addCustomAction(PlaybackState.CustomAction.Builder(b.id, b.label, iconRes(b.icon)).build())
        }
        session?.setPlaybackState(st.build())
    }

    private fun build(s: WorkoutState): Notification {
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        b.setSmallIcon(R.drawable.ic_stat_workout)
            .setContentTitle(s.title)
            .setContentText(subtitle(s))
            .setSubText(s.dayName)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_WORKOUT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        artwork?.let { b.setLargeIcon(it) }

        // Für Android 12 und älter: Knöpfe direkt in der Benachrichtigung.
        val all = buildList {
            s.buttons.firstOrNull()?.let { add(it) }
            s.primary?.let { add(it.copy(icon = if (s.mode == "set") "pause" else "play")) }
            addAll(s.buttons.drop(1))
        }.take(5)
        all.forEachIndexed { i, btn ->
            val pi = PendingIntent.getBroadcast(
                this, 100 + i,
                Intent(this, WorkoutActionReceiver::class.java).putExtra(WorkoutActionReceiver.EXTRA_ACTION, btn.id),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            b.addAction(Notification.Action.Builder(Icon.createWithResource(this, iconRes(btn.icon)), btn.label, pi).build())
        }
        val style = Notification.MediaStyle().setMediaSession(session?.sessionToken)
        when {
            all.size >= 3 -> style.setShowActionsInCompactView(0, 1, 2)
            all.size == 2 -> style.setShowActionsInCompactView(0, 1)
            all.size == 1 -> style.setShowActionsInCompactView(0)
        }
        b.setStyle(style)
        return b.build()
    }

    override fun onDestroy() {
        handler.removeCallbacks(ticker)
        session?.release()
        session = null
        instance = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "workout"
        private const val NOTIFICATION_ID = 42
        private var current: WorkoutState? = null
        private var instance: WorkoutService? = null
        private var artwork: Bitmap? = null
        private var artworkKey = ""

        fun setArtwork(key: String, png: ByteArray) {
            if (key == artworkKey) return
            artworkKey = key
            artwork = BitmapFactory.decodeByteArray(png, 0, png.size)
        }

        fun hasArtwork(key: String) = key == artworkKey

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

        /** Feste Zuordnung, damit der Release-Build die Symbole nicht entfernt. */
        fun iconRes(name: String): Int = when (name) {
            "undo" -> R.drawable.ic_m_undo
            "minus" -> R.drawable.ic_m_minus
            "plus" -> R.drawable.ic_m_plus
            "check" -> R.drawable.ic_m_check
            "flag" -> R.drawable.ic_m_flag
            "rest_minus" -> R.drawable.ic_m_rest_minus
            "rest_plus" -> R.drawable.ic_m_rest_plus
            "level1" -> R.drawable.ic_m_level1
            "level2" -> R.drawable.ic_m_level2
            "level3" -> R.drawable.ic_m_level3
            "equal" -> R.drawable.ic_m_equal
            "one" -> R.drawable.ic_m_one
            "two" -> R.drawable.ic_m_two
            "save" -> R.drawable.ic_m_save
            "play" -> R.drawable.ic_m_play
            "pause" -> R.drawable.ic_m_pause
            else -> R.drawable.ic_stat_workout
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
