package com.hydrawav3.hydrawav3

import io.flutter.plugin.common.EventChannel

object BackgroundSessionChannels {
    @Volatile
    var eventSink: EventChannel.EventSink? = null

    fun emit(event: Map<String, Any?>) {
        eventSink?.success(event)
    }
}
