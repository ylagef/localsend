package org.localsend.localsend_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Actions can only act on a live Dart session. Never restart an engine to accept stale requests. */
object ReceiveNotifications {
    private const val REQUESTS = "localsend_receive_requests"
    private const val RESULTS = "localsend_receive_results"
    private const val TAG = "localsend_receive"
    var channel: MethodChannel? = null
    var visible = false
    private val sessions = mutableMapOf<String, String>()

    fun enable(context: Context, name: String): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(REQUESTS, name, NotificationManager.IMPORTANCE_HIGH))
            manager.createNotificationChannel(NotificationChannel(RESULTS, name + " · ✓", NotificationManager.IMPORTANCE_DEFAULT))
        }
        return allowed(context, REQUESTS) && allowed(context, RESULTS)
    }

    private fun allowed(context: Context, id: String): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 26 ||
            manager.getNotificationChannel(id)?.importance != NotificationManager.IMPORTANCE_NONE)
    }

    fun show(context: Context, args: Map<*, *>): Boolean {
        if (visible) return false
        val session = args["sessionId"] as? String ?: return false
        val kind = args["kind"] as? String ?: return false
        val pending = kind == "pending"
        val channelId = if (pending) REQUESTS else RESULTS
        if (!allowed(context, channelId)) return false
        val title = args["title"] as? String ?: "LocalSend"
        val body = args["body"] as? String ?: ""
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "org.localsend.OPEN_RECEIVE"
            data = Uri.parse("localsend://receive/$session/$kind")
            putExtra("sessionId", session)
            putExtra("kind", kind)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val open = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId) else Notification.Builder(context)
        builder.setSmallIcon(R.drawable.ic_receive_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setCategory(if (pending) Notification.CATEGORY_RECOMMENDATION else Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion((if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId) else Notification.Builder(context))
                .setSmallIcon(R.drawable.ic_receive_notification).setContentTitle("LocalSend").build())
            .setOngoing(pending)
            .setAutoCancel(!pending)
        if (pending) {
            for ((key, action) in listOf("primaryLabel" to "accept", "secondaryLabel" to "reject")) {
                val label = args[key] as? String ?: continue
                val actionIntent = Intent(context, ReceiveNotificationReceiver::class.java).apply {
                    data = Uri.parse("localsend://receive/$session/$action")
                    putExtra("sessionId", session)
                    putExtra("kind", kind)
                    putExtra("action", action)
                }
                val pi = PendingIntent.getBroadcast(context, 0, actionIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val button = Notification.Action.Builder(null, label, pi)
                if (Build.VERSION.SDK_INT >= 31 && action == "accept") button.setAuthenticationRequired(true)
                builder.addAction(button.build())
            }
        }
        // Replacing by session also clears its pending actions when a result arrives.
        context.getSystemService(NotificationManager::class.java).notify(TAG + session, 1, builder.build())
        sessions[session] = kind
        return true
    }

    fun isPending(session: String) = sessions[session] == "pending"

    fun clearOrphanedRequests(context: Context) {
        if (Build.VERSION.SDK_INT < 23) return
        val manager = context.getSystemService(NotificationManager::class.java)
        for (entry in manager.activeNotifications) {
            val tag = entry.tag ?: continue
            val request = if (Build.VERSION.SDK_INT >= 26) entry.notification.channelId == REQUESTS
                else entry.notification.category == Notification.CATEGORY_RECOMMENDATION
            if (tag.startsWith(TAG) && request && !isPending(tag.removePrefix(TAG))) manager.cancel(tag, entry.id)
        }
    }

    fun remove(context: Context, session: String) {
        if (sessions[session] == "done" || sessions[session] == "error") return
        context.getSystemService(NotificationManager::class.java).cancel(TAG + session, 1)
        sessions.remove(session)
    }

    fun hide(context: Context) {
        sessions.filterValues { it == "pending" }.keys.toList().forEach { remove(context, it) }
    }
}

class ReceiveNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val session = intent.getStringExtra("sessionId") ?: return
        val kind = intent.getStringExtra("kind") ?: return
        val action = intent.getStringExtra("action") ?: return
        if (kind != "pending" || action !in listOf("accept", "reject")) return
        val channel = ReceiveNotifications.channel
        if (channel == null) {
            ReceiveNotifications.remove(context, session)
            return
        }
        val pending = goAsync()
        val handler = Handler(Looper.getMainLooper())
        var finished = false
        fun finish() {
            if (!finished) {
                finished = true
                pending.finish()
            }
        }
        val timeout = Runnable { finish() }
        handler.postDelayed(timeout, 9000)
        channel.invokeMethod("onReceiveAlertAction", mapOf("sessionId" to session, "kind" to kind, "action" to action), object : MethodChannel.Result {
            override fun success(result: Any?) {
                if ((result as? Map<*, *>)?.get("success") == true || !ReceiveNotifications.isPending(session)) ReceiveNotifications.remove(context, session)
                handler.removeCallbacks(timeout)
                finish()
            }
            override fun error(code: String, message: String?, details: Any?) { handler.removeCallbacks(timeout); finish() }
            override fun notImplemented() { handler.removeCallbacks(timeout); finish() }
        })
    }
}
