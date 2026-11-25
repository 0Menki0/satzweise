package de.satzweise.satzweise

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Verbindet die Flutter-App mit der Trainings-Benachrichtigung.
 *
 * Flutter → Android: "update" (Inhalt und Knöpfe) und "stop".
 * Android → Flutter: "action" mit der ID des Knopfs, der auf dem
 * Sperrbildschirm gedrückt wurde.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ActionBus.attach(channel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as Map<String, Any?>
                    askNotificationPermission()
                    WorkoutService.update(this, WorkoutState.fromMap(args))
                    result.success(null)
                }
                "stop" -> {
                    WorkoutService.stop(this)
                    result.success(null)
                }
                "pendingActions" -> result.success(ActionBus.drain())
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        ActionBus.detach()
        super.onDestroy()
    }

    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    companion object {
        const val CHANNEL = "satzweise/workout_notification"
    }
}
