package io.github.gameon223.memora.background

import io.github.gameon223.memora.bridge.SchedulePolicy

/**
 * The queue policy as plain values, so workers can read back what the app
 * last asked for. Kept apart from SharedPreferences to stay testable.
 */
object SchedulePolicyCodec {
    const val KEY_IMMEDIATE = "immediate"
    const val KEY_PAUSED = "paused"
    const val KEY_WINDOW_START = "window_start_minutes"
    const val KEY_WINDOW_END = "window_end_minutes"
    const val KEY_USES_NETWORK = "uses_network"
    const val KEY_HAS_WORK = "has_work"

    const val DEFAULT_WINDOW_START = 60L
    const val DEFAULT_WINDOW_END = 420L

    val keys = listOf(
        KEY_IMMEDIATE,
        KEY_PAUSED,
        KEY_WINDOW_START,
        KEY_WINDOW_END,
        KEY_USES_NETWORK,
        KEY_HAS_WORK,
    )

    fun toMap(policy: SchedulePolicy): Map<String, Any> = mapOf(
        KEY_IMMEDIATE to policy.immediate,
        KEY_PAUSED to policy.paused,
        KEY_WINDOW_START to policy.windowStartMinutes,
        KEY_WINDOW_END to policy.windowEndMinutes,
        KEY_USES_NETWORK to policy.requiresUnmeteredNetwork,
        KEY_HAS_WORK to policy.hasWork,
    )

    /** Missing or oddly typed values fall back to the overnight default. */
    fun fromMap(values: Map<String, Any?>): SchedulePolicy = SchedulePolicy(
        immediate = values.boolean(KEY_IMMEDIATE),
        paused = values.boolean(KEY_PAUSED),
        windowStartMinutes = values.long(KEY_WINDOW_START, DEFAULT_WINDOW_START),
        windowEndMinutes = values.long(KEY_WINDOW_END, DEFAULT_WINDOW_END),
        requiresUnmeteredNetwork = values.boolean(KEY_USES_NETWORK),
        hasWork = values.boolean(KEY_HAS_WORK),
    )

    private fun Map<String, Any?>.boolean(key: String): Boolean = this[key] as? Boolean ?: false

    private fun Map<String, Any?>.long(key: String, fallback: Long): Long = when (val value = this[key]) {
        is Long -> value
        is Int -> value.toLong()
        else -> fallback
    }
}
