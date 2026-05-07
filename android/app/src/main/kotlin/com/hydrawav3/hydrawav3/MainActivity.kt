package com.hydrawav3.hydrawav3

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodsChannelName = "hydrawav3/background_session/methods"
    private val eventsChannelName = "hydrawav3/background_session/events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodsChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        android.util.Log.d("MAIN_ACTIVITY", "requestNotificationPermission called")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            android.util.Log.d("MAIN_ACTIVITY", "Android 13+ detected, checking permission")
                            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) 
                                != PackageManager.PERMISSION_GRANTED) {
                                // Disabled as requested: do not show permission prompt.
                                // android.util.Log.d("MAIN_ACTIVITY", "Permission NOT granted, requesting...")
                                // ActivityCompat.requestPermissions(
                                //     this,
                                //     arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                //     1001
                                // )
                                result.success(false)
                            } else {
                                android.util.Log.d("MAIN_ACTIVITY", "Permission already granted")
                                result.success(true)
                            }
                        } else {
                            android.util.Log.d("MAIN_ACTIVITY", "Android < 13, Permission not needed")
                            result.success(true)
                        }
                    }
                    "startService" -> {
                        val startedAt = call.argument<Number>("startedAtEpochMs")?.toLong()
                            ?: System.currentTimeMillis()
                        val deviceIds = call.argument<List<String>>("deviceIds") ?: emptyList<String>()
                        val deviceNames = call.argument<List<String>>("deviceNames") ?: emptyList<String>()
                        val protocolName = call.argument<String>("protocolName") ?: "Unknown Protocol"
                        
                        val intent = Intent(this, BleForegroundService::class.java).apply {
                            action = BleForegroundService.ACTION_START
                            putExtra(BleForegroundService.EXTRA_STARTED_AT_EPOCH_MS, startedAt)
                            putExtra("deviceIds", ArrayList(deviceIds))
                            putExtra("deviceNames", ArrayList(deviceNames))
                            putExtra("protocolName", protocolName)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "pauseService" -> {
                        val intent = Intent(this, BleForegroundService::class.java).apply {
                            action = BleForegroundService.ACTION_PAUSE
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "resumeService" -> {
                        val intent = Intent(this, BleForegroundService::class.java).apply {
                            action = BleForegroundService.ACTION_RESUME
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "pauseDevice" -> {
                        val deviceId = call.argument<String>("deviceId")
                        val intent = Intent(this, BleForegroundService::class.java).apply {
                            action = BleForegroundService.ACTION_PAUSE_DEVICE
                            putExtra("deviceId", deviceId)
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "resumeDevice" -> {
                        val deviceId = call.argument<String>("deviceId")
                        val intent = Intent(this, BleForegroundService::class.java).apply {
                            action = BleForegroundService.ACTION_RESUME_DEVICE
                            putExtra("deviceId", deviceId)
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "stopDevice" -> {
                        val deviceId = call.argument<String>("deviceId")
                        val intent = Intent(this, BleForegroundService::class.java).apply {
                            action = BleForegroundService.ACTION_STOP_DEVICE
                            putExtra("deviceId", deviceId)
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "stopService" -> {
                        val intent = Intent(this, BleForegroundService::class.java).apply {
                            action = BleForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventsChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    BackgroundSessionChannels.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    BackgroundSessionChannels.eventSink = null
                }
            })
    }
}
