package com.tapvoice.app.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import com.tapvoice.app.storage.MappingStore
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/** High-reliability, low-latency audio playback engine for mapped controller buttons and previews. */
object TapAudioEngine {
    private const val TAG = "TapAudioEngine"
    private lateinit var context: Context
    private val audioPathsByButton = ConcurrentHashMap<String, String>()
    private val buttonByKey = ConcurrentHashMap<Int, String>()
    private val activePlayers = ConcurrentHashMap<Int, MediaPlayer>()
    private val streamIdCounter = AtomicInteger(1)

    private val audioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    fun initialize(appContext: Context) {
        context = appContext.applicationContext
        audioPathsByButton.clear()
        buttonByKey.clear()
        MappingStore(context).all().forEach { raw ->
            val buttonId = raw["buttonId"] as? String ?: return@forEach
            val keyCode = (raw["keyCode"] as? Number)?.toInt() ?: 0
            val path = raw["audioPath"] as? String
            if (path != null && File(path).exists()) {
                load(buttonId, keyCode, path)
            }
        }
    }

    fun load(buttonId: String, keyCode: Int, path: String) {
        if (!File(path).exists()) {
            Log.w(TAG, "Audio file does not exist for $buttonId: $path")
            return
        }
        audioPathsByButton[buttonId] = path
        MappingStore.keyCodesFor(buttonId, keyCode).forEach { code ->
            buttonByKey[code] = buttonId
        }
    }

    fun unload(buttonId: String) {
        audioPathsByButton.remove(buttonId)
        buttonByKey.entries.removeIf { it.value == buttonId }
    }

    fun playByKeyCode(keyCode: Int): Boolean {
        return playByKeyCodeWithButton(keyCode) != null
    }

    /** Returns the resolved slot only when its audio actually started. */
    fun playByKeyCodeWithButton(keyCode: Int): String? {
        val button = buttonByKey[keyCode]
            ?: MappingStore(context).findByKey(keyCode)?.buttonId
            ?: return null
        return button.takeIf(::playByButton)
    }

    fun playByButton(buttonId: String): Boolean {
        return playByButtonStream(buttonId) != 0
    }

    fun playByButtonStream(buttonId: String): Int {
        val path = audioPathsByButton[buttonId]
            ?: MappingStore(context).findByButton(buttonId)?.audioPath
            ?: run {
                Log.w(TAG, "No audio path found for button $buttonId")
                return 0
            }

        val file = File(path)
        if (!file.exists() || file.length() == 0L) {
            Log.w(TAG, "Audio file invalid for button $buttonId: $path")
            return 0
        }

        // TapVoice is a soundboard: a newly triggered recording always takes
        // priority over an unfinished one, rather than mixing both clips.
        stopAll()
        val streamId = streamIdCounter.getAndIncrement()
        try {
            val player = MediaPlayer()
            player.setAudioAttributes(audioAttributes)
            player.setDataSource(file.absolutePath)
            player.setOnCompletionListener { mp ->
                activePlayers.remove(streamId)
                runCatching { mp.release() }
            }
            player.setOnErrorListener { mp, what, extra ->
                Log.e(TAG, "MediaPlayer error (what: $what, extra: $extra) for stream $streamId")
                activePlayers.remove(streamId)
                runCatching { mp.release() }
                true
            }
            player.prepare()
            player.start()
            activePlayers[streamId] = player
            return streamId
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play audio for button $buttonId at $path", e)
            activePlayers.remove(streamId)?.let { runCatching { it.release() } }
            return 0
        }
    }

    fun pause(streamId: Int) {
        activePlayers[streamId]?.let { player ->
            runCatching {
                if (player.isPlaying) {
                    player.pause()
                }
            }.onFailure { Log.w(TAG, "Failed to pause stream $streamId", it) }
        }
    }

    fun resume(streamId: Int) {
        activePlayers[streamId]?.let { player ->
            runCatching {
                player.start()
            }.onFailure { Log.w(TAG, "Failed to resume stream $streamId", it) }
        }
    }

    fun stop(streamId: Int) {
        activePlayers.remove(streamId)?.let { player ->
            runCatching {
                if (player.isPlaying) {
                    player.stop()
                }
                player.release()
            }.onFailure { Log.w(TAG, "Failed to stop stream $streamId", it) }
        }
    }

    fun stopAll() {
        activePlayers.forEach { (id, player) ->
            runCatching {
                if (player.isPlaying) {
                    player.stop()
                }
                player.release()
            }
        }
        activePlayers.clear()
    }
}
