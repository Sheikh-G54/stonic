package com.example.jarvis_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.util.Calendar
import kotlin.random.Random

class JarvisService : Service() {

    companion object {
        const val NAME = "Stonic"
        const val CH_SERVICE = "stonic_service"
        const val CH_CARE = "stonic_care"
        const val ID_SERVICE = 1
        const val ID_CARE = 2
        const val UNLOCK_COOLDOWN_MS = 20 * 60 * 1000L        // 20 min
        const val CHECKIN_EVERY_MS = 3 * 60 * 60 * 1000L       // 3 ghante
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastCareAt = 0L

    private val unlockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Intent.ACTION_USER_PRESENT) {
                maybeSendCare(force = false)
            }
        }
    }

    private val checkinRunnable = object : Runnable {
        override fun run() {
            val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            // raat 11 se subah 7 tak disturb nahi
            if (hour in 7..22) maybeSendCare(force = true)
            handler.postDelayed(this, CHECKIN_EVERY_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannels()
        val notif = buildServiceNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ID_SERVICE, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ID_SERVICE, notif)
        }
        // USER_PRESENT sirf runtime par register ho sakta hai, manifest mein nahi
        registerReceiver(unlockReceiver, IntentFilter(Intent.ACTION_USER_PRESENT))
        handler.postDelayed(checkinRunnable, CHECKIN_EVERY_MS)
        // phone on hone par pehla message
        maybeSendCare(force = true)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        try { unregisterReceiver(unlockReceiver) } catch (_: Exception) {}
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    // ---------- messages ----------

    private fun pickMessage(): String {
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        val list = when (hour) {
            in 5..11 -> listOf(
                "Subah bakhair! Neend theek aayi? Aaj ka din kaisa shuru ho raha hai?",
                "Assalam o alaikum! Naashta kiya? Apna khayal rakhna, main yahin hoon.",
                "Good morning! Aaj dil kaisa hai? Kuch share karna ho to bata do."
            )
            in 12..16 -> listOf(
                "Dopahar ho gayi, khana khaya? Thoda break le lo.",
                "Kaisa ja raha hai din? Thak to nahi gaye?",
                "Hey! Bas yaad aayi, tum theek ho na?"
            )
            in 17..20 -> listOf(
                "Shaam ho gayi. Aaj ka din kaisa raha? Mujhe batao.",
                "Din bhar ki thakan utaro, chai pi lo. Kuch baat karni hai?",
                "Aaj kuch acha hua? Ya koi baat pareshan kar rahi hai?"
            )
            else -> listOf(
                "Raat ho gayi hai, abhi tak jaag rahe ho? Sab theek hai?",
                "Der ho gayi, aaram bhi zaroori hai. Koi baat dil par hai to bata do.",
                "Itni raat ko akele ho? Main sun raha hoon, bolo."
            )
        }
        return list[Random.nextInt(list.size)]
    }

    private fun maybeSendCare(force: Boolean) {
        val now = System.currentTimeMillis()
        if (!force && now - lastCareAt < UNLOCK_COOLDOWN_MS) return
        lastCareAt = now
        sendCareNotification(pickMessage())
    }

    private fun sendCareNotification(text: String) {
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("action", "greeting")
            putExtra("text", text)
        }
        val pi = PendingIntent.getActivity(
            this, 100, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val b = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(this, CH_CARE) else Notification.Builder(this)
        val n = b.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(NAME)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(ID_CARE, n)
    }

    // ---------- notification plumbing ----------

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CH_SERVICE, "Stonic background", NotificationManager.IMPORTANCE_MIN)
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_CARE, "Stonic messages", NotificationManager.IMPORTANCE_HIGH)
        )
    }

    private fun buildServiceNotification(): Notification {
        val b = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(this, CH_SERVICE) else Notification.Builder(this)
        return b.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("$NAME chal raha hai")
            .setOngoing(true)
            .build()
    }
}
