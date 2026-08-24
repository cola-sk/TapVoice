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
        val handled = TapAudioEngine.playByKeyCode(event.keyCode)
        if (handled) TapEventBus.keyPressed(event.keyCode)
        return handled
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit
}
