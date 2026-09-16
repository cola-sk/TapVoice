package com.tapvoice.app.storage

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class AudioItem(
    val id: String,
    val path: String,
    val durationMs: Long = 0,
    val name: String = "",
    val createdAt: Long = System.currentTimeMillis(),
) {
    fun toMap() = mapOf(
        "id" to id,
        "path" to path,
        "durationMs" to durationMs,
        "name" to name,
        "createdAt" to createdAt
    )
}

data class AudioMapping(
    val buttonId: String,
    val keyCode: Int,
    val audios: List<AudioItem> = emptyList(),
    val legacyAudioPath: String? = null,
    val legacyDurationMs: Long = 0,
    val updatedAt: Long = System.currentTimeMillis(),
) {
    val audioPath: String? get() = audios.firstOrNull()?.path ?: legacyAudioPath
    val durationMs: Long get() = audios.firstOrNull()?.durationMs ?: legacyDurationMs
    val hasAudio: Boolean get() = audios.isNotEmpty() || (!audioPath.isNullOrBlank())

    fun toMap() = mapOf(
        "buttonId" to buttonId,
        "keyCode" to keyCode,
        "audios" to audios.map { it.toMap() },
        "audioPath" to audioPath,
        "durationMs" to durationMs,
        "updatedAt" to updatedAt
    )
}

class MappingStore(context: Context) {
    private val prefs = context.getSharedPreferences("tapvoice_mappings", Context.MODE_PRIVATE)
    private val storageKey = "mappings"

    fun all(): List<Map<String, Any?>> = read().map { it.toMap() }

    fun findByKey(keyCode: Int) = read().firstOrNull {
        it.hasAudio && keyCode in keyCodesFor(it.buttonId, it.keyCode)
    }
    fun findByButton(buttonId: String) = read().firstOrNull { it.buttonId == buttonId }

    fun save(buttonId: String, keyCode: Int, audioPath: String?): AudioMapping {
        val current = findByButton(buttonId)
        val item = AudioMapping(
            buttonId = buttonId,
            keyCode = keyCode,
            audios = current?.audios ?: emptyList(),
            legacyAudioPath = audioPath ?: current?.audioPath,
            legacyDurationMs = current?.durationMs ?: 0
        )
        replace(item)
        return item
    }

    fun addOrUpdateAudio(
        buttonId: String,
        audioId: String?,
        path: String,
        durationMs: Long,
        name: String? = null
    ): Pair<AudioMapping, AudioItem> {
        val current = findByButton(buttonId) ?: AudioMapping(buttonId, DEFAULT_KEYS[buttonId] ?: 0)
        val existingAudios = current.audios.toMutableList()
        val index = if (audioId != null) existingAudios.indexOfFirst { it.id == audioId } else -1

        val audioItem: AudioItem
        if (index >= 0) {
            val old = existingAudios[index]
            audioItem = old.copy(
                path = path,
                durationMs = durationMs,
                name = name ?: old.name.ifBlank { "Audio ${index + 1}" }
            )
            existingAudios[index] = audioItem
        } else {
            if (existingAudios.size >= 10) {
                throw IllegalStateException("Maximum 10 audios allowed per button")
            }
            val newId = audioId ?: "${buttonId}_${System.currentTimeMillis()}"
            audioItem = AudioItem(
                id = newId,
                path = path,
                durationMs = durationMs,
                name = name ?: "Audio ${existingAudios.size + 1}"
            )
            existingAudios.add(audioItem)
        }

        val updated = current.copy(audios = existingAudios, updatedAt = System.currentTimeMillis())
        replace(updated)
        return Pair(updated, audioItem)
    }

    fun saveAudio(buttonId: String, audioPath: String, durationMs: Long): AudioMapping {
        return addOrUpdateAudio(buttonId, null, audioPath, durationMs).first
    }

    fun deleteAudio(buttonId: String, audioId: String): AudioMapping? {
        val current = findByButton(buttonId) ?: return null
        val existingAudios = current.audios.toMutableList()
        val itemToDelete = existingAudios.firstOrNull { it.id == audioId }
        if (itemToDelete != null) {
            existingAudios.remove(itemToDelete)
            runCatching { java.io.File(itemToDelete.path).delete() }
        }
        val updated = current.copy(audios = existingAudios, updatedAt = System.currentTimeMillis())
        replace(updated)
        return updated
    }

    fun delete(buttonId: String): AudioMapping? {
        val items = read().toMutableList()
        val item = items.firstOrNull { it.buttonId == buttonId }
        if (item != null) {
            item.audios.forEach { audio ->
                runCatching { java.io.File(audio.path).delete() }
            }
            item.audioPath?.let { runCatching { java.io.File(it).delete() } }
            items.remove(item)
            write(items)
        }
        return item
    }

    private fun replace(item: AudioMapping) {
        val items = read().filterNot { it.buttonId == item.buttonId }.toMutableList()
        items.add(item)
        write(items)
    }

    private fun read(): List<AudioMapping> = runCatching {
        val raw = prefs.getString(storageKey, "[]") ?: "[]"
        val array = JSONArray(raw)
        List(array.length()) { index ->
            val value = array.getJSONObject(index)
            val buttonId = value.getString("buttonId")
            val keyCode = value.getInt("keyCode")
            val audiosArray = value.optJSONArray("audios")
            val audios = if (audiosArray != null) {
                List(audiosArray.length()) { i ->
                    val a = audiosArray.getJSONObject(i)
                    AudioItem(
                        id = a.getString("id"),
                        path = a.getString("path"),
                        durationMs = a.optLong("durationMs"),
                        name = a.optString("name").takeIf { it.isNotBlank() } ?: "Audio ${i + 1}",
                        createdAt = a.optLong("createdAt", System.currentTimeMillis())
                    )
                }
            } else {
                val legacyPath = value.optString("audioPath").takeIf { it.isNotBlank() }
                if (legacyPath != null && java.io.File(legacyPath).exists()) {
                    listOf(
                        AudioItem(
                            id = "${buttonId}_legacy",
                            path = legacyPath,
                            durationMs = value.optLong("durationMs"),
                            name = "Audio 1",
                            createdAt = value.optLong("updatedAt", System.currentTimeMillis())
                        )
                    )
                } else {
                    emptyList()
                }
            }

            AudioMapping(
                buttonId = buttonId,
                keyCode = keyCode,
                audios = audios,
                legacyAudioPath = value.optString("audioPath").takeIf { it.isNotBlank() },
                legacyDurationMs = value.optLong("durationMs"),
                updatedAt = value.optLong("updatedAt")
            )
        }
    }.getOrDefault(emptyList())

    private fun write(items: List<AudioMapping>) {
        val array = JSONArray()
        items.forEach { item ->
            array.put(JSONObject().apply {
                put("buttonId", item.buttonId)
                put("keyCode", item.keyCode)
                put("audioPath", item.audioPath)
                put("durationMs", item.durationMs)
                put("updatedAt", item.updatedAt)
                put("audios", JSONArray().apply {
                    item.audios.forEach { audio ->
                        put(JSONObject().apply {
                            put("id", audio.id)
                            put("path", audio.path)
                            put("durationMs", audio.durationMs)
                            put("name", audio.name)
                            put("createdAt", audio.createdAt)
                        })
                    }
                })
            })
        }
        prefs.edit().putString(storageKey, array.toString()).apply()
    }

    companion object {
        val DEFAULT_KEYS = mapOf(
            "btn_dpad_up" to 19, "btn_dpad_down" to 20, "btn_dpad_left" to 21, "btn_dpad_right" to 22,
            "btn_x" to 99, "btn_y" to 100, "btn_a" to 96, "btn_b" to 97,
            "btn_minus" to 69, "btn_plus" to 81, "btn_star" to 17, "btn_home" to 3,
            "btn_l1" to 102, "btn_r1" to 103,
        )

        /**
         * Keyboard-mode aliases emitted by the 8BitDo Micro (2DC8:9021).
         *
         * These were verified from the device's Linux input events.  The
         * previous W/S/A/D and I/J/K/M assumptions overlap other physical
         * buttons on the real device (for example S is Home, not D-pad Down),
         * which made the wrong recording play.
         */
        private val KEYBOARD_KEYS = mapOf(
            "btn_dpad_up" to 31, "btn_dpad_down" to 32,
            "btn_dpad_left" to 33, "btn_dpad_right" to 34,
            "btn_x" to 36, "btn_y" to 37, "btn_a" to 35, "btn_b" to 38,
            "btn_minus" to 42, "btn_plus" to 43,
            // The Star key emits no Android input event in the tested K profile.
            "btn_home" to 47,
            "btn_l1" to 45, "btn_r1" to 44,
        )

        /** Extra key codes emitted by the Micro's D-input profile. */
        private val D_INPUT_KEYS = mapOf(
            "btn_minus" to 109, // KEYCODE_BUTTON_SELECT
            "btn_plus" to 108, // KEYCODE_BUTTON_START
            "btn_home" to 110, // KEYCODE_BUTTON_MODE
        )

        /**
         * Includes a user-learned primary code, the standard controller code,
         * and the standard keyboard-mode code.  Set removes duplicates.
         */
        fun keyCodesFor(buttonId: String, primaryKeyCode: Int): Set<Int> =
            buildSet {
                if (primaryKeyCode != 0) add(primaryKeyCode)
                DEFAULT_KEYS[buttonId]?.let(::add)
                KEYBOARD_KEYS[buttonId]?.let(::add)
                D_INPUT_KEYS[buttonId]?.let(::add)
            }
    }
}
