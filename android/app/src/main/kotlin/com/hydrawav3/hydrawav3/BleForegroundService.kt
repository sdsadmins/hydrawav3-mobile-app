package com.hydrawav3.hydrawav3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class BleForegroundService : Service() {
    private val timerHandler = Handler(Looper.getMainLooper())
    private var startedAtEpochMs: Long = 0L
    private var status: String = STATUS_IDLE
    private var protocolName: String = "Hydrawav Session"
    private var deviceStates: MutableMap<String, String> = LinkedHashMap()
    private var deviceNames: MutableMap<String, String> = LinkedHashMap()

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

        // CRITICAL: When launched via startForegroundService(), Android requires
        // startForeground() to be called within ~5s for EVERY start — otherwise it
        // throws ForegroundServiceDidNotStartInTimeException and kills the app.
        // A session that completes instantly (e.g. a 1s protocol) can race a STOP
        // ahead of START, so we satisfy the contract first thing for every action.
        try {
            startForeground(NOTIFICATION_ID, buildNotification())
        } catch (e: Exception) {
            android.util.Log.e("BLE_SERVICE", "startForeground failed: $e")
        }

        when (action) {
            ACTION_START -> {
                startedAtEpochMs = intent?.getLongExtra(EXTRA_STARTED_AT_EPOCH_MS, System.currentTimeMillis())
                    ?: System.currentTimeMillis()
                status = STATUS_RUNNING
                protocolName = intent?.getStringExtra("protocolName")?.takeIf { it.isNotEmpty() } ?: protocolName
                applyDeviceExtras(intent)
                updateNotification()
                emitState("started")
                startTicking()
            }
            ACTION_UPDATE -> {
                // Live sync from the Flutter session engine: protocol switch
                // (Protocol Plus), per-device status changes, overall status, and
                // the timer anchor. Keeps the notification consistent with the app.
                intent?.getStringExtra("protocolName")?.takeIf { it.isNotEmpty() }?.let { protocolName = it }
                intent?.getStringExtra("status")?.takeIf { it.isNotEmpty() }?.let { status = it }
                val startedAt = intent?.getLongExtra(EXTRA_STARTED_AT_EPOCH_MS, -1L) ?: -1L
                if (startedAt > 0L) startedAtEpochMs = startedAt
                applyDeviceExtras(intent)
                if (status == STATUS_RUNNING) startTicking() else stopTicking()
                updateNotification()
                emitState("updated")
            }
            ACTION_PAUSE -> {
                status = STATUS_PAUSED
                deviceStates.keys.forEach { if (deviceStates[it] == STATUS_RUNNING) deviceStates[it] = STATUS_PAUSED }
                stopTicking()
                emitState("paused")
                updateNotification()
            }
            ACTION_RESUME -> {
                status = STATUS_RUNNING
                deviceStates.keys.forEach { if (deviceStates[it] == STATUS_PAUSED) deviceStates[it] = STATUS_RUNNING }
                startTicking()
                emitState("resumed")
                updateNotification()
            }
            ACTION_PAUSE_DEVICE -> {
                intent?.getStringExtra("deviceId")?.let { deviceStates[it] = STATUS_PAUSED }
                emitState("device_paused")
                updateNotification()
            }
            ACTION_RESUME_DEVICE -> {
                intent?.getStringExtra("deviceId")?.let { deviceStates[it] = STATUS_RUNNING }
                emitState("device_resumed")
                updateNotification()
            }
            ACTION_STOP_DEVICE -> {
                intent?.getStringExtra("deviceId")?.let { deviceStates[it] = STATUS_STOPPED }
                emitState("device_stopped")
                updateNotification()
            }
            ACTION_PAUSE_ALL_DEVICES -> {
                // Pause control tapped from the notification.
                deviceStates.keys.forEach { deviceId ->
                    if (deviceStates[deviceId] == STATUS_RUNNING) {
                        sendBleCommandToDevice(deviceId, 0x02)
                        deviceStates[deviceId] = STATUS_PAUSED
                    }
                }
                status = STATUS_PAUSED
                stopTicking()
                updateNotification()
                emitState("all_paused")
            }
            ACTION_RESUME_ALL_DEVICES -> {
                // Resume control tapped from the notification.
                deviceStates.keys.forEach { deviceId ->
                    if (deviceStates[deviceId] == STATUS_PAUSED) {
                        sendBleCommandToDevice(deviceId, 0x04)
                        deviceStates[deviceId] = STATUS_RUNNING
                    }
                }
                status = STATUS_RUNNING
                startTicking()
                updateNotification()
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

    /** Replace the device id/name/status maps from intent extras (parallel lists). */
    private fun applyDeviceExtras(intent: Intent?) {
        if (intent == null) return
        val deviceIds = intent.getStringArrayListExtra("deviceIds") ?: return
        if (deviceIds.isEmpty()) return
        val names = intent.getStringArrayListExtra("deviceNames")
        val statuses = intent.getStringArrayListExtra("deviceStatuses")

        val newStates = LinkedHashMap<String, String>()
        val newNames = LinkedHashMap<String, String>()
        for (i in deviceIds.indices) {
            val id = deviceIds[i]
            newNames[id] = names?.getOrNull(i)?.takeIf { it.isNotEmpty() } ?: deviceNames[id] ?: shortId(id)
            newStates[id] = statuses?.getOrNull(i)?.takeIf { it.isNotEmpty() } ?: deviceStates[id] ?: status
        }
        deviceStates = newStates
        deviceNames = newNames
    }

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

    private fun updateNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val deviceCount = deviceStates.size
        val runningDevices = deviceStates.filterValues { it == STATUS_RUNNING }.size
        val pausedDevices = deviceStates.filterValues { it == STATUS_PAUSED }.size

        val contentText = when {
            status == STATUS_PAUSED -> "Paused"
            deviceCount == 0 -> "Connecting…"
            deviceCount == 1 -> "1 device running"
            pausedDevices > 0 -> "$runningDevices running • $pausedDevices paused"
            else -> "$runningDevices of $deviceCount devices running"
        }

        val builder = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(protocolName)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setLargeIcon(appLargeIcon())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setColorized(true)
            .setColor(0xFF1E1B17.toInt())
            .setContentIntent(buildContentIntent())

        // Live elapsed timer (counts up) while running; frozen label when paused.
        if (status == STATUS_RUNNING) {
            builder.setUsesChronometer(true)
            builder.setWhen(startedAtEpochMs)
            builder.setShowWhen(true)
        } else {
            builder.setUsesChronometer(false)
            builder.setShowWhen(false)
        }

        // Pause/Resume/Stop notification actions intentionally removed — session
        // control is done in-app only. The notification is now status-only.

        return builder.build()
    }

    private fun appLargeIcon(): Icon? {
        return try {
            Icon.createWithResource(this, R.mipmap.ic_launcher)
        } catch (e: Exception) {
            null
        }
    }

    private fun buildContentIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        } ?: Intent()
        return PendingIntent.getActivity(
            this, REQ_OPEN, launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun shortId(deviceId: String): String {
        return if (deviceId.length >= 4) deviceId.substring(deviceId.length - 4) else deviceId
    }

    private fun sendBleCommandToDevice(deviceId: String, commandByte: Int) {
        try {
            BackgroundSessionChannels.emit(
                mapOf(
                    "type" to "ble_command",
                    "deviceId" to deviceId,
                    "command" to commandByte
                )
            )
            android.util.Log.d("BLE_SERVICE", "Sent BLE command 0x${commandByte.toString(16)} to device $deviceId")
        } catch (e: Exception) {
            android.util.Log.e("BLE_SERVICE", "Failed to send BLE command to device $deviceId: $e")
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Hydrawav Session",
            // LOW so repeated live updates never buzz/heads-up; it stays an
            // ongoing status notification while a session runs.
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps your session running and shows live status while the app is in the background"
            setShowBadge(true)
        }
        nm.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_START = "com.hydrawav3.hydrawav3.BG_SESSION_START"
        const val ACTION_UPDATE = "com.hydrawav3.hydrawav3.BG_SESSION_UPDATE"
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

        private const val REQ_OPEN = 100
    }
}
