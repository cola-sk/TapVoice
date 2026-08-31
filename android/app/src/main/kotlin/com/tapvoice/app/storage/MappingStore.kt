package com.tapvoice.app.storage

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class AudioMapping(
    val buttonId: String,
    val keyCode: Int,
    val audioPath: String?,
    val durationMs: Long = 0,
    val updatedAt: Long = System.currentTimeMillis(),
) {
    fun toMap() = mapOf("buttonId" to buttonId, "keyCode" to keyCode, "audioPath" to audioPath, "durationMs" to durationMs, "updatedAt" to updatedAt)
}

class MappingStore(context: Context) {
    private val prefs = context.getSharedPreferences("tapvoice_mappings", Context.MODE_PRIVATE)
    private val storageKey = "mappings"

    fun all(): List<Map<String, Any?>> = read().map { it.toMap() }

    /**
     * A Micro in keyboard (K) mode emits keyboard key codes, while the same
     * physical button in controller mode emits BUTTON_* codes.  Keep both
     * forms associated with the recording slot so stored recordings work in
     * either mode.
     */
    fun findByKey(keyCode: Int) = read().firstOrNull {
        it.audioPath != null && keyCode in keyCodesFor(it.buttonId, it.keyCode)
    }
    fun findByButton(buttonId: String) = read().firstOrNull { it.buttonId == buttonId }

    fun save(buttonId: String, keyCode: Int, audioPath: String?): AudioMapping {
        val current = findByButton(buttonId)
        val item = AudioMapping(buttonId, keyCode, audioPath ?: current?.audioPath, current?.durationMs ?: 0)
        replace(item)
        return item
    }

    fun saveAudio(buttonId: String, audioPath: String, durationMs: Long): AudioMapping {
        val current = findByButton(buttonId) ?: AudioMapping(buttonId, DEFAULT_KEYS[buttonId] ?: 0, null)
        val item = current.copy(audioPath = audioPath, durationMs = durationMs, updatedAt = System.currentTimeMillis())
        replace(item)
        return item
    }

    fun delete(buttonId: String): AudioMapping? {
        val items = read().toMutableList()
        val item = items.firstOrNull { it.buttonId == buttonId }
        if (item != null) {
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
            AudioMapping(
                value.getString("buttonId"), value.getInt("keyCode"),
                value.optString("audioPath").takeIf { it.isNotBlank() },
                value.optLong("durationMs"), value.optLong("updatedAt"),
            )
        }
    }.getOrDefault(emptyList())

    private fun write(items: List<AudioMapping>) {
        val array = JSONArray()
        items.forEach { item ->
            array.put(JSONObject().apply {
                put("buttonId", item.buttonId); put("keyCode", item.keyCode)
                put("audioPath", item.audioPath); put("durationMs", item.durationMs); put("updatedAt", item.updatedAt)
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
