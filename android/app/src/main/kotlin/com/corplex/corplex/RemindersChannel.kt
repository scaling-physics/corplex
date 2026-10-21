package com.corplex.corplex

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Date reminders (`corplex/reminders`): local notifications through an
 * inexact [AlarmManager] alarm (no exact-alarm permission), posted by
 * [ReminderReceiver]. Nothing is touched at registration: the managers are
 * fetched on a call. `schedule` asks for POST_NOTIFICATIONS the first time
 * (Android 13+), never at launch. Alarms don't survive a reboot; Dart
 * re-derives them from the notes when the app next starts.
 *
 * A tap opens [MainActivity] with the note id, which goes back as `open`
 * once Dart has said `ready`.
 */
class RemindersChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "corplex/reminders")
    private var ready = false
    private val pending = ArrayList<String>()
    private var askedPermission = false

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "ready" -> {
                        ready = true
                        val queued = ArrayList(pending)
                        pending.clear()
                        queued.forEach { channel.invokeMethod("open", it) }
                        result.success(null)
                    }
                    "schedule" -> {
                        schedule(call.argument<List<Map<String, Any>>>("items") ?: emptyList(),
                            call.argument<String>("channelName"))
                        result.success(null)
                    }
                    "cancel" -> {
                        (call.arguments as? List<*>)?.forEach { cancel((it as Number).toInt()) }
                        result.success(null)
                    }
                    "cancelAll" -> {
                        val prefs = prefs()
                        prefs.all.keys.forEach { cancel(it.toInt()) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("reminders_failed", e.message, null)
            }
        }
    }

    /** A notification was tapped (or the app launched from one). */
    fun opened(noteId: String) {
        if (ready) channel.invokeMethod("open", noteId) else pending.add(noteId)
    }

    private fun prefs() = activity.getSharedPreferences("corplex_reminders", Context.MODE_PRIVATE)

    private fun alarmIntent(id: Int, extras: Map<String, Any>?, flags: Int): PendingIntent? {
        val intent = Intent(activity, ReminderReceiver::class.java).setAction("com.corplex.REMINDER")
        extras?.let {
            intent.putExtra("title", it["title"] as String)
            intent.putExtra("body", it["body"] as String)
            intent.putExtra("noteId", it["noteId"] as String)
            intent.putExtra("channelName", it["channelName"] as String)
        }
        return PendingIntent.getBroadcast(
            activity, id, intent, flags or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun schedule(items: List<Map<String, Any>>, channelName: String?) {
        if (Build.VERSION.SDK_INT >= 33 && !askedPermission &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED) {
            askedPermission = true
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4711)
        }
        val alarms = activity.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val editor = prefs().edit()
        for (item in items) {
            val id = (item["id"] as Number).toInt()
            val at = (item["at"] as Number).toLong()
            val extras = HashMap<String, Any>(item)
            extras["channelName"] = channelName ?: "Reminders"
            val pi = alarmIntent(id, extras, PendingIntent.FLAG_UPDATE_CURRENT) ?: continue
            alarms.set(AlarmManager.RTC_WAKEUP, at, pi)
            editor.putLong(id.toString(), at)
        }
        editor.apply()
    }

    private fun cancel(id: Int) {
        val alarms = activity.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmIntent(id, null, PendingIntent.FLAG_NO_CREATE)?.let {
            alarms.cancel(it)
            it.cancel()
        }
        prefs().edit().remove(id.toString()).apply()
    }
}

/** Posts the notification when the alarm fires. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: return
        val noteId = intent.getStringExtra("noteId") ?: return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "corplex_reminders"
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId, intent.getStringExtra("channelName") ?: "Reminders",
                    NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = Intent(context, MainActivity::class.java)
            .setAction("com.corplex.OPEN_NOTE")
            .putExtra("reminderNote", noteId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tap = PendingIntent.getActivity(
            context, noteId.hashCode(), open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_corplex)
            .setContentTitle(title)
            .setContentText(intent.getStringExtra("body") ?: "")
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra("body") ?: ""))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        try {
            manager.notify(noteId.hashCode() xor (title.hashCode() * 31), notification)
        } catch (e: SecurityException) {
            // Notifications not allowed: nothing to show.
        }
    }
}
