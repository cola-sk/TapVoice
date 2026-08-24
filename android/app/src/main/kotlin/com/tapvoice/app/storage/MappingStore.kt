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

    fun findByKey(keyCode: Int) = read().firstOrNull { it.keyCode == keyCode && it.audioPath != null }
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
    }
}
