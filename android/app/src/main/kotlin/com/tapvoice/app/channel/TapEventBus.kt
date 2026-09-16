package com.tapvoice.app.channel

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object TapEventBus : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    fun keyPressed(
        keyCode: Int,
        buttonId: String? = null,
        durationMs: Long = 0,
        audioId: String? = null
    ) = send(
        buildMap {
            put("type", "keyPressed")
            put("keyCode", keyCode)
            buttonId?.let { put("buttonId", it) }
            if (durationMs > 0) put("durationMs", durationMs)
            audioId?.let { put("audioId", it) }
        },
    )
    fun learnedKey(keyCode: Int) = send(mapOf("type" to "learnedKey", "keyCode" to keyCode))

    private fun send(event: Map<String, Any>) {
        mainHandler.post { sink?.success(event) }
    }
}
