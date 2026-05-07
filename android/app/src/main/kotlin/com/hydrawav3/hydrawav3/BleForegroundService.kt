package com.hydrawav3.hydrawav3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

class BleForegroundService : Service() {
    private val timerHandler = Handler(Looper.getMainLooper())
    private var startedAtEpochMs: Long = 0L
    private var status: String = STATUS_IDLE
    private var deviceStates: MutableMap<String, String> = mutableMapOf()
    private var deviceNames: MutableMap<String, String> = mutableMapOf()

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (status == STATUS_RUNNING) {
                val elapsedMs = (System.currentTimeMillis() - startedAtEpochMs).coerceAtLeast(0L)
                BackgroundSessionChannels.emit(
                    mapOf(
                        "type" to "tick",
                        "status" to status,
                        "startedAtEpochMs" to startedAtEpochMs,
                        "elapsedMs" to elapsedMs
                    )
                )
            }
            timerHandler.postDelayed(this, 1000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        when (action) {
            ACTION_START -> {
                android.util.Log.d("BLE_SERVICE", "startForeground called for ACTION_START")
                startedAtEpochMs = intent?.getLongExtra(EXTRA_STARTED_AT_EPOCH_MS, System.currentTimeMillis())
                    ?: System.currentTimeMillis()
                status = STATUS_RUNNING
                
                // Add device info from intent
                val deviceIds = intent?.getStringArrayListExtra("deviceIds")
                val deviceNamesList = intent?.getStringArrayListExtra("deviceNames")
                val protocolName = intent?.getStringExtra("protocolName") ?: "Unknown Protocol"
                
                if (deviceIds != null && deviceNamesList != null) {
                    android.util.Log.d("BLE_SERVICE", "Adding ${deviceIds.size} devices to notification")
                    for (i in deviceIds.indices) {
                        val deviceId = deviceIds[i]
                        val deviceName = if (i < deviceNamesList.size) deviceNamesList[i] else "Device $i"
                        deviceStates[deviceId] = STATUS_RUNNING
                        deviceNames[deviceId] = deviceName
                        android.util.Log.d("BLE_SERVICE", "Added device: $deviceId as $deviceName")
                    }
                } else {
                    android.util.Log.d("BLE_SERVICE", "No device IDs or names received")
                }
                
                startForeground(NOTIFICATION_ID, buildNotification("Session running"))
                emitState("started")
                startTicking()
            }
            ACTION_PAUSE -> {
                status = STATUS_PAUSED
                emitState("paused")
                updateNotification("Session paused")
            }
            ACTION_RESUME -> {
                status = STATUS_RUNNING
                emitState("resumed")
                updateNotification("Session running")
            }
            ACTION_PAUSE_DEVICE -> {
                val deviceId = intent?.getStringExtra("deviceId")
                if (deviceId != null) {
                    deviceStates[deviceId] = STATUS_PAUSED
                    updateNotification("Device $deviceId paused")
                }
                emitState("device_paused")
            }
            ACTION_RESUME_DEVICE -> {
                val deviceId = intent?.getStringExtra("deviceId")
                if (deviceId != null) {
                    deviceStates[deviceId] = STATUS_RUNNING
                    updateNotification("Device $deviceId resumed")
                }
                emitState("device_resumed")
            }
            ACTION_STOP_DEVICE -> {
                val deviceId = intent?.getStringExtra("deviceId")
                if (deviceId != null) {
                    deviceStates[deviceId] = STATUS_STOPPED
                    updateNotification("Device $deviceId stopped")
                }
                emitState("device_stopped")
            }
            ACTION_PAUSE_ALL_DEVICES -> {
                // Send actual BLE pause command to all running devices
                android.util.Log.d("BLE_SERVICE", "Sending BLE pause command to all running devices")
                deviceStates.keys.forEach { deviceId ->
                    if (deviceStates[deviceId] == STATUS_RUNNING) {
                        // Send BLE pause byte (0x02)
                        sendBleCommandToDevice(deviceId, 0x02)
                        deviceStates[deviceId] = STATUS_PAUSED
                    }
                }
                updateNotification("All devices paused")
                emitState("all_paused")
            }
            ACTION_RESUME_ALL_DEVICES -> {
                // Send actual BLE resume command to all paused devices
                android.util.Log.d("BLE_SERVICE", "Sending BLE resume command to all paused devices")
                deviceStates.keys.forEach { deviceId ->
                    if (deviceStates[deviceId] == STATUS_PAUSED) {
                        // Send BLE resume byte (0x04)
                        sendBleCommandToDevice(deviceId, 0x04)
                        deviceStates[deviceId] = STATUS_RUNNING
                    }
                }
                updateNotification("All devices resumed")
                emitState("all_resumed")
            }
            ACTION_STOP -> {
                status = STATUS_STOPPED
                emitState("stopped")
                stopTicking()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopTicking()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startTicking() {
        timerHandler.removeCallbacks(tickRunnable)
        timerHandler.post(tickRunnable)
    }

    private fun stopTicking() {
        timerHandler.removeCallbacks(tickRunnable)
    }

    private fun emitState(eventType: String) {
        val elapsedMs = (System.currentTimeMillis() - startedAtEpochMs).coerceAtLeast(0L)
        BackgroundSessionChannels.emit(
            mapOf(
                "type" to eventType,
                "status" to status,
                "startedAtEpochMs" to startedAtEpochMs,
                "elapsedMs" to elapsedMs
            )
        )
    }

    private fun updateNotification(message: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(message))
    }

    private fun buildNotification(message: String): Notification {
        android.util.Log.d("BLE_SERVICE", "Building notification: $message")
        
        // Create Spotify-style multi-device notification
        val deviceCount = deviceStates.size
        val runningDevices = deviceStates.filterValues { it == STATUS_RUNNING }.size
        val pausedDevices = deviceStates.filterValues { it == STATUS_PAUSED }.size
        
        val contentText = if (deviceCount > 1) {
            "$runningDevices devices running • $deviceCount total"
        } else if (deviceCount == 1) {
            val deviceStatus = deviceStates.values.first()
            val deviceName = getDeviceName(deviceStates.keys.first())
            "$deviceName: $deviceStatus"
        } else {
            "No devices connected"
        }
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Hydrawav Session")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(false)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setStyle(createSpotifyStyleNotification())
            .addAction(createDynamicControlActions())
            .build()
    }
    
    private fun createSpotifyStyleNotification(): NotificationCompat.Style {
        val builder = NotificationCompat.BigTextStyle()
        
        if (deviceStates.isEmpty()) {
            builder.bigText("No devices connected")
        } else {
            val deviceInfo = deviceStates.entries.joinToString("\n\n") { (deviceId, status) ->
                val deviceName = getDeviceName(deviceId)
                val statusIcon = when (status) {
                    STATUS_RUNNING -> "▶️"
                    STATUS_PAUSED -> "⏸️"
                    STATUS_STOPPED -> "⏹️"
                    else -> "⚪"
                }
                "$statusIcon $deviceName\nStatus: $status"
            }
            builder.bigText(deviceInfo)
        }
        
        return builder
    }
    
    private fun createDynamicControlActions(): NotificationCompat.Action {
        // Check if any devices are running to determine button state
        val runningDevices = deviceStates.filterValues { it == STATUS_RUNNING }.size
        val pausedDevices = deviceStates.filterValues { it == STATUS_PAUSED }.size
        
        return if (runningDevices > 0) {
            // Show Pause button when devices are running
            val pauseIntent = Intent(this, BleForegroundService::class.java).apply {
                action = ACTION_PAUSE_ALL_DEVICES
            }
            val pausePendingIntent = PendingIntent.getService(this, 1, pauseIntent, PendingIntent.FLAG_IMMUTABLE)
            
            NotificationCompat.Action.Builder(
                android.R.drawable.ic_media_pause,
                "Pause",
                pausePendingIntent
            ).build()
        } else if (pausedDevices > 0) {
            // Show Resume button when devices are paused
            val resumeIntent = Intent(this, BleForegroundService::class.java).apply {
                action = ACTION_RESUME_ALL_DEVICES
            }
            val resumePendingIntent = PendingIntent.getService(this, 2, resumeIntent, PendingIntent.FLAG_IMMUTABLE)
            
            NotificationCompat.Action.Builder(
                android.R.drawable.ic_media_play,
                "Resume",
                resumePendingIntent
            ).build()
        } else {
            // Show Stop button when no devices are active
            val stopIntent = Intent(this, BleForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            val stopPendingIntent = PendingIntent.getService(this, 3, stopIntent, PendingIntent.FLAG_IMMUTABLE)
            
            NotificationCompat.Action.Builder(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPendingIntent
            ).build()
        }
    }
    
    private fun getDeviceName(deviceId: String): String {
        // Use stored device name or fallback to last 4 chars
        return deviceNames[deviceId] ?: deviceId.substring(deviceId.length - 4)
    }
    
    private fun sendBleCommandToDevice(deviceId: String, commandByte: Int) {
        try {
            // Send BLE command to Flutter side for actual device control
            BackgroundSessionChannels.emit(mapOf(
                "type" to "ble_command",
                "deviceId" to deviceId,
                "command" to commandByte
            ))
            android.util.Log.d("BLE_SERVICE", "Sent BLE command 0x${commandByte.toString(16)} to device $deviceId")
        } catch (e: Exception) {
            android.util.Log.e("BLE_SERVICE", "Failed to send BLE command to device $deviceId: $e")
        }
    }

    private fun ensureNotificationChannel() {
        android.util.Log.d("BLE_SERVICE", "ensureNotificationChannel called")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            android.util.Log.d("BLE_SERVICE", "Android < 8, skipping channel creation")
            return
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = nm.getNotificationChannel(CHANNEL_ID)
        if (existing != null) {
            android.util.Log.d("BLE_SERVICE", "Channel already exists")
            return
        }
        
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Hydrawav BLE Session",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Keeps session active while app is in background"
            enableLights(true)
            enableVibration(true)
            setShowBadge(true)
        }
        nm.createNotificationChannel(channel)
        android.util.Log.d("BLE_SERVICE", "Notification channel created successfully")
    }

    companion object {
        const val ACTION_START = "com.hydrawav3.hydrawav3.BG_SESSION_START"
        const val ACTION_PAUSE = "com.hydrawav3.hydrawav3.BG_SESSION_PAUSE"
        const val ACTION_RESUME = "com.hydrawav3.hydrawav3.BG_SESSION_RESUME"
        const val ACTION_STOP = "com.hydrawav3.hydrawav3.BG_SESSION_STOP"
        const val ACTION_PAUSE_DEVICE = "com.hydrawav3.hydrawav3.BG_SESSION_PAUSE_DEVICE"
        const val ACTION_RESUME_DEVICE = "com.hydrawav3.hydrawav3.BG_SESSION_RESUME_DEVICE"
        const val ACTION_STOP_DEVICE = "com.hydrawav3.hydrawav3.BG_SESSION_STOP_DEVICE"
        const val ACTION_PAUSE_ALL_DEVICES = "com.hydrawav3.hydrawav3.BG_SESSION_PAUSE_ALL_DEVICES"
        const val ACTION_RESUME_ALL_DEVICES = "com.hydrawav3.hydrawav3.BG_SESSION_RESUME_ALL_DEVICES"
        const val EXTRA_STARTED_AT_EPOCH_MS = "startedAtEpochMs"
        const val EXTRA_DEVICE_ID = "deviceId"

        const val STATUS_IDLE = "idle"
        const val STATUS_RUNNING = "running"
        const val STATUS_PAUSED = "paused"
        const val STATUS_STOPPED = "stopped"

        private const val CHANNEL_ID = "hydrawav_ble_session_channel"
        private const val NOTIFICATION_ID = 31001
    }
}
