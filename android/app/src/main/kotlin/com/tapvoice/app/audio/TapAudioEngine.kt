package com.tapvoice.app.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import com.tapvoice.app.storage.AudioItem
import com.tapvoice.app.storage.MappingStore
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/** High-reliability, low-latency audio playback engine for mapped controller buttons and previews. */
object TapAudioEngine {
    private const val TAG = "TapAudioEngine"
    private lateinit var context: Context
    private val audiosByButton = ConcurrentHashMap<String, MutableList<AudioItem>>()
    private val buttonByKey = ConcurrentHashMap<Int, String>()
    private val activePlayers = ConcurrentHashMap<Int, MediaPlayer>()
    private val streamIdCounter = AtomicInteger(1)
    private val random = java.util.Random()

    private val audioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    data class PlayResult(
        val streamId: Int,
        val buttonId: String,
        val audioId: String,
        val path: String,
        val durationMs: Long
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "streamId" to streamId,
            "buttonId" to buttonId,
            "audioId" to audioId,
            "path" to path,
            "durationMs" to durationMs
        )
    }

    fun initialize(appContext: Context) {
        context = appContext.applicationContext
        reload()
    }

    fun reload() {
        audiosByButton.clear()
        buttonByKey.clear()
        MappingStore(context).all().forEach { raw ->
            val buttonId = raw["buttonId"] as? String ?: return@forEach
            val keyCode = (raw["keyCode"] as? Number)?.toInt() ?: 0
            val items = mutableListOf<AudioItem>()
            @Suppress("UNCHECKED_CAST")
            val audiosRaw = raw["audios"] as? List<Map<String, Any?>>
            audiosRaw?.forEach { a ->
                val path = a["path"] as? String
                val id = a["id"] as? String ?: ""
                val dur = (a["durationMs"] as? Number)?.toLong() ?: 0L
                val name = a["name"] as? String ?: ""
                if (path != null && File(path).exists()) {
                    items.add(AudioItem(id, path, dur, name))
                }
            }
            if (items.isEmpty()) {
                val legacyPath = raw["audioPath"] as? String
                val legacyDur = (raw["durationMs"] as? Number)?.toLong() ?: 0L
                if (legacyPath != null && File(legacyPath).exists()) {
                    items.add(AudioItem("${buttonId}_legacy", legacyPath, legacyDur, "Audio 1"))
                }
            }
            if (items.isNotEmpty()) {
                audiosByButton[buttonId] = items
                MappingStore.keyCodesFor(buttonId, keyCode).forEach { code ->
                    buttonByKey[code] = buttonId
                }
            }
        }
    }

    fun load(buttonId: String, keyCode: Int, path: String) {
        reload()
    }

    fun unload(buttonId: String) {
        audiosByButton.remove(buttonId)
        buttonByKey.entries.removeIf { it.value == buttonId }
    }

    fun playByKeyCode(keyCode: Int): Boolean {
        return playByKeyCodeWithButton(keyCode) != null
    }

    /** Returns PlayResult when audio starts for the resolved button slot. */
    fun playByKeyCodeWithButton(keyCode: Int): PlayResult? {
        val button = buttonByKey[keyCode]
            ?: MappingStore(context).findByKey(keyCode)?.buttonId
            ?: return null
        return playButton(button)
    }

    fun playByButton(buttonId: String): Boolean {
        return playButton(buttonId) != null
    }

    fun playByButtonStream(buttonId: String): Int {
        return playButton(buttonId)?.streamId ?: 0
    }

    fun playButton(buttonId: String, specificAudioId: String? = null): PlayResult? {
        var items = audiosByButton[buttonId]
        if (items.isNullOrEmpty()) {
            reload()
            items = audiosByButton[buttonId]
        }
        if (items.isNullOrEmpty()) {
            Log.w(TAG, "No audios found for button $buttonId")
            return null
        }

        val chosen = if (specificAudioId != null) {
            items.firstOrNull { it.id == specificAudioId } ?: items[0]
        } else {
            // Randomly select one audio file bound to this button
            if (items.size == 1) items[0] else items[random.nextInt(items.size)]
        }

        val file = File(chosen.path)
        if (!file.exists() || file.length() == 0L) {
            Log.w(TAG, "Audio file invalid for button $buttonId: ${chosen.path}")
            return null
        }

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
            return PlayResult(
                streamId = streamId,
                buttonId = buttonId,
                audioId = chosen.id,
                path = chosen.path,
                durationMs = chosen.durationMs
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play audio for button $buttonId at ${chosen.path}", e)
            activePlayers.remove(streamId)?.let { runCatching { it.release() } }
            return null
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
