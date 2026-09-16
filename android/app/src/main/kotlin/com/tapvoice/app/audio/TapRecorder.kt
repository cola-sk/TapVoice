package com.tapvoice.app.audio

import android.content.Context
import android.media.MediaMetadataRetriever
import android.media.MediaRecorder
import android.os.Build
import java.io.File

data class SavedRecording(
    val buttonId: String,
    val audioId: String?,
    val path: String,
    val durationMs: Long
)

@Suppress("DEPRECATION")
class TapRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var tempFile: File? = null
    private var buttonId: String? = null
    private var targetAudioId: String? = null
    private var startedAt = 0L
    private var paused = false

    fun start(targetButtonId: String, audioId: String? = null) {
        cancel()
        val directory = File(context.filesDir, "audios").apply { mkdirs() }
        tempFile = File(directory, ".recording_${System.currentTimeMillis()}.m4a")
        buttonId = targetButtonId
        targetAudioId = audioId
        val newRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else MediaRecorder()
        recorder = newRecorder.apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioEncodingBitRate(128_000)
            setAudioSamplingRate(44_100)
            setOutputFile(tempFile!!.absolutePath)
            prepare()
            start()
        }
        startedAt = System.currentTimeMillis()
        paused = false
    }

    fun amplitude(): Int = runCatching { recorder?.maxAmplitude ?: 0 }.getOrDefault(0)

    fun pause() {
        val active = recorder ?: throw IllegalStateException("No active recording")
        if (!paused) {
            active.pause()
            paused = true
        }
    }

    fun resume() {
        val active = recorder ?: throw IllegalStateException("No active recording")
        if (paused) {
            active.resume()
            paused = false
        }
    }

    fun stop(): SavedRecording? {
        val active = recorder ?: return null
        val target = buttonId ?: return null
        val chosenAudioId = targetAudioId
        val source = tempFile ?: return null
        runCatching { active.stop() }.onFailure { cleanup(); return null }
        runCatching { active.release() }
        recorder = null

        val fileKey = chosenAudioId ?: "${target}_${System.currentTimeMillis()}"
        val destination = File(source.parentFile, "$fileKey.m4a")
        try {
            if (destination.exists()) destination.delete()
            source.copyTo(destination, overwrite = true)
            source.delete()
        } catch (e: Exception) {
            cleanup()
            return null
        }

        val duration = readDuration(destination).let { if (it > 0) it else (System.currentTimeMillis() - startedAt) }
        tempFile = null
        buttonId = null
        targetAudioId = null
        paused = false
        return SavedRecording(target, chosenAudioId, destination.absolutePath, duration)
    }

    fun cancel() = cleanup()

    private fun cleanup() {
        runCatching { recorder?.stop() }
        runCatching { recorder?.release() }
        recorder = null
        tempFile?.delete()
        tempFile = null
        buttonId = null
        paused = false
    }

    private fun readDuration(file: File): Long = runCatching {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
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
}
