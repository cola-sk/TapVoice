package com.tapvoice.app

import android.Manifest
import android.app.Activity
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.provider.OpenableColumns
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.tapvoice.app.audio.TapAudioEngine
import com.tapvoice.app.audio.TapRecorder
import com.tapvoice.app.channel.TapEventBus
import com.tapvoice.app.storage.MappingStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val methods = "com.tapvoice.app/bridge"
    private val events = "com.tapvoice.app/events"
    private lateinit var recorder: TapRecorder
    private var pendingUploadResult: MethodChannel.Result? = null
    private var pendingUploadButtonId: String? = null
    private val interceptedKeyCodes = mutableSetOf<Int>()
    private var activeDpadButtonId: String? = null
    private var handledDpadMotion = false

    /**
     * Some Android builds route D-input gamepad keys to Flutter focus
     * navigation before an AccessibilityService sees them.  When TapVoice is
     * visible, consume a mapped key here so DPAD buttons do not move focus to
     * the Play/Record controls instead of playing their audio.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            val buttonId = TapAudioEngine.playByKeyCodeWithButton(keyCode)
            if (buttonId != null) {
                interceptedKeyCodes += keyCode
                TapEventBus.keyPressed(keyCode, buttonId)
                return true
            }
        } else if (event.action == KeyEvent.ACTION_UP && keyCode in interceptedKeyCodes) {
            interceptedKeyCodes -= keyCode
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    /**
     * In D-input mode the Micro reports its D-pad as HAT_X/HAT_Y joystick
     * motion rather than DPAD key events.  Handle the press edge once and
     * consume the motion so Flutter's focus traversal cannot move to the
     * sidebar controls.
     */
    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.action != MotionEvent.ACTION_MOVE ||
            !event.isFromSource(InputDevice.SOURCE_JOYSTICK)
        ) {
            return super.dispatchGenericMotionEvent(event)
        }

        val horizontal = event.getAxisValue(MotionEvent.AXIS_HAT_X)
        val vertical = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
        val buttonId = when {
            vertical <= -0.5f -> "btn_dpad_up"
            vertical >= 0.5f -> "btn_dpad_down"
            horizontal <= -0.5f -> "btn_dpad_left"
            horizontal >= 0.5f -> "btn_dpad_right"
            else -> null
        }

        if (buttonId == activeDpadButtonId) {
            return if (handledDpadMotion) true else super.dispatchGenericMotionEvent(event)
        }

        if (buttonId == null) {
            val wasHandled = handledDpadMotion
            activeDpadButtonId = null
            handledDpadMotion = false
            return if (wasHandled) true else super.dispatchGenericMotionEvent(event)
        }

        activeDpadButtonId = buttonId
        handledDpadMotion = false
        if (TapAudioEngine.playByButton(buttonId)) {
            handledDpadMotion = true
            TapEventBus.keyPressed(MappingStore.DEFAULT_KEYS[buttonId] ?: 0, buttonId)
            return true
        }

        return super.dispatchGenericMotionEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TapAudioEngine.initialize(applicationContext)
        recorder = TapRecorder(applicationContext)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, events)
            .setStreamHandler(TapEventBus)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methods)
            .setMethodCallHandler(::handleCall)
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getMappings" -> result.success(MappingStore(applicationContext).all())
                "saveMapping" -> {
                    val buttonId = call.requiredString("buttonId")
                    val keyCode = call.requiredInt("keyCode")
                    val path = call.argument<String>("audioPath")
                    MappingStore(applicationContext).save(buttonId, keyCode, path)
                    if (path != null) TapAudioEngine.load(buttonId, keyCode, path)
                    result.success(null)
                }
                "deleteMapping" -> {
                    val buttonId = call.requiredString("buttonId")
                    MappingStore(applicationContext).delete(buttonId)?.audioPath?.let { path ->
                        java.io.File(path).delete()
                    }
                    TapAudioEngine.unload(buttonId)
                    result.success(null)
                }
                "playButton" -> {
                    val buttonId = call.requiredString("buttonId")
                    result.success(TapAudioEngine.playByButtonStream(buttonId))
                }
                "pausePlayback" -> {
                    TapAudioEngine.pause(call.requiredInt("streamId"))
                    result.success(null)
                }
                "resumePlayback" -> {
                    TapAudioEngine.resume(call.requiredInt("streamId"))
                    result.success(null)
                }
                "stopPlayback" -> {
                    TapAudioEngine.stop(call.requiredInt("streamId"))
                    result.success(null)
                }
                "stopAllPlayback" -> {
                    TapAudioEngine.stopAll()
                    result.success(null)
                }
                "startRecording" -> {
                    if (!hasRecordPermission()) {
                        result.error("microphone_permission", "Microphone permission is required", null)
                    } else {
                        recorder.start(call.requiredString("buttonId"))
                        result.success(null)
                    }
                }
                "stopRecording" -> {
                    val saved = recorder.stop()
                    if (saved == null) result.error("recording_failed", "No recording was saved", null)
                    else {
                        val mapping = MappingStore(applicationContext).saveAudio(saved.buttonId, saved.path, saved.durationMs)
                        TapAudioEngine.load(mapping.buttonId, mapping.keyCode, mapping.audioPath ?: saved.path)
                        result.success(mapOf("path" to saved.path, "durationMs" to saved.durationMs))
                    }
                }
                "cancelRecording" -> { recorder.cancel(); result.success(null) }
                "pauseRecording" -> { recorder.pause(); result.success(null) }
                "resumeRecording" -> { recorder.resume(); result.success(null) }
                "pickAudio" -> {
                    if (pendingUploadResult != null) {
                        result.error("picker_busy", "An audio picker is already open", null)
                    } else {
                        pendingUploadResult = result
                        pendingUploadButtonId = call.requiredString("buttonId")
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/*"
                        }, AUDIO_PICK_REQUEST)
                    }
                }
                "getRecordingAmplitude" -> result.success(recorder.amplitude())
                "requestMicrophonePermission" -> { requestMicrophonePermission(); result.success(null) }
                "isMicrophonePermissionGranted" -> result.success(hasRecordPermission())
                "isAccessibilityEnabled" -> result.success(isAccessibilityEnabled())
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "startForegroundService" -> {
                    val intent = Intent(this, com.tapvoice.app.service.TapForegroundService::class.java)
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "stopForegroundService" -> {
                    stopService(Intent(this, com.tapvoice.app.service.TapForegroundService::class.java))
                    result.success(null)
                }
                "requestNotificationPermission" -> { requestNotificationPermission(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("native_error", error.message, null)
        }
    }

    @Deprecated("Use Activity Result APIs when migrating this host")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == AUDIO_PICK_REQUEST) {
            handlePickedAudio(if (resultCode == Activity.RESULT_OK) data?.data else null)
        }
    }

    private fun hasRecordPermission() = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun requestMicrophonePermission() = ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 41)

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42)
        }
    }

    private fun handlePickedAudio(uri: Uri?) {
        val result = pendingUploadResult ?: return
        val buttonId = pendingUploadButtonId
        pendingUploadResult = null
        pendingUploadButtonId = null

        if (uri == null || buttonId == null) {
            result.error("cancelled", "Audio selection was cancelled", null)
            return
        }

        try {
            val directory = File(filesDir, "audios").apply { mkdirs() }
            val destination = File(directory, "$buttonId.${audioExtension(uri)}")
            val input = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Unable to read selected audio")
            input.use { source ->
                destination.outputStream().use { target -> source.copyTo(target) }
            }

            val store = MappingStore(applicationContext)
            val previousPath = store.findByButton(buttonId)?.audioPath
            val durationMs = readDuration(destination)
            val mapping = store.saveAudio(buttonId, destination.absolutePath, durationMs)
            if (previousPath != null && previousPath != destination.absolutePath) {
                File(previousPath).delete()
            }
            TapAudioEngine.load(mapping.buttonId, mapping.keyCode, destination.absolutePath)
            result.success(mapping.toMap())
        } catch (error: Exception) {
            result.error("upload_failed", error.message, null)
        }
    }

    private fun audioExtension(uri: Uri): String {
        val displayName = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        val fromName = displayName?.substringAfterLast('.', "")?.lowercase()
            ?.takeIf { it.matches(Regex("[a-z0-9]{1,5}")) }
        if (fromName != null) return fromName
        return when (contentResolver.getType(uri)) {
            "audio/mpeg" -> "mp3"
            "audio/wav", "audio/x-wav" -> "wav"
            "audio/ogg" -> "ogg"
            "audio/aac" -> "aac"
            else -> "m4a"
        }
    }

    private fun readDuration(file: File): Long = runCatching {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0
        } finally {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    retriever.close()
                } else {
                    retriever.release()
                }
            } catch (_: Exception) {}
        }
    }.getOrDefault(0)

    companion object {
        private const val AUDIO_PICK_REQUEST = 4101
    }

    private fun isAccessibilityEnabled(): Boolean {
        val manager = getSystemService(Context.ACCESSIBILITY_SERVICE) as android.view.accessibility.AccessibilityManager
        val expected = ComponentName(this, com.tapvoice.app.service.TapAccessibilityService::class.java)
        return manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { ComponentName.unflattenFromString(it.id) == expected }
    }

    private fun MethodCall.requiredString(name: String) = argument<String>(name)
        ?: throw IllegalArgumentException("Missing $name")
    private fun MethodCall.requiredInt(name: String) = argument<Number>(name)?.toInt()
        ?: throw IllegalArgumentException("Missing $name")
}
