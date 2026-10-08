package com.example.jarvis_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val a = intent.action
        if (a == Intent.ACTION_BOOT_COMPLETED ||
            a == "android.intent.action.QUICKBOOT_POWERON" ||
            a == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            // sirf tab start karo jab user ne app ek baar khol kar enable kiya ho
            val enabled = context
                .getSharedPreferences("stonic", Context.MODE_PRIVATE)
                .getBoolean("enabled", false)
            if (!enabled) return
            val svc = Intent(context, JarvisService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(svc)
            else context.startService(svc)
        }
    }
}
