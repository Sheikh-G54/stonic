package com.example.jarvis_app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "stonic/service"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    askNotificationPermission()
                    getSharedPreferences("stonic", Context.MODE_PRIVATE)
                        .edit().putBoolean("enabled", true).apply()
                    startJarvisService()
                    result.success(true)
                }
                "disable" -> {
                    getSharedPreferences("stonic", Context.MODE_PRIVATE)
                        .edit().putBoolean("enabled", false).apply()
                    stopService(Intent(this, JarvisService::class.java))
                    result.success(true)
                }
                "batterySettings" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                "launchAction" -> {
                    // notification tap se aaya hua data
                    val a = intent?.getStringExtra("action")
                    val t = intent?.getStringExtra("text")
                    intent?.removeExtra("action")
                    result.success(if (a == null) null else mapOf("action" to a, "text" to t))
                }
                else -> result.notImplemented()
            }
        }
    }

    // app pehle se khuli ho aur notification tap ho
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val a = intent.getStringExtra("action") ?: return
        channel?.invokeMethod(
            "onLaunchAction",
            mapOf("action" to a, "text" to intent.getStringExtra("text"))
        )
        intent.removeExtra("action")
    }

    private fun startJarvisService() {
        val svc = Intent(this, JarvisService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(svc) else startService(svc)
    }

    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 11)
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            i.data = Uri.parse("package:$packageName")
            startActivity(i)
        }
    }
}
