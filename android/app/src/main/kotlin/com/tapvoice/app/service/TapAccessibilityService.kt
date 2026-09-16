package com.tapvoice.app.service

import android.accessibilityservice.AccessibilityService
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import com.tapvoice.app.audio.TapAudioEngine
import com.tapvoice.app.channel.TapEventBus

class TapAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        TapAudioEngine.initialize(applicationContext)
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN || event.repeatCount > 0) return false
        val playResult = TapAudioEngine.playByKeyCodeWithButton(event.keyCode)
        if (playResult != null) {
            TapEventBus.keyPressed(
                event.keyCode,
                playResult.buttonId,
                playResult.durationMs,
                playResult.audioId
            )
        }
        return playResult != null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit
}
