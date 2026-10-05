package io.github.gameon223.memora.inference.llm

/** The answer to "can this device hold this model right now". */
sealed interface Headroom {
    data object Allowed : Headroom

    /**
     * [code] is the error code the Dart side sees, so it can tell a device
     * that will never fit the model from one that is merely busy.
     */
    data class Refused(val code: String, val message: String) : Headroom
}

/**
 * Decides whether a model file can be loaded from the numbers
 * `ActivityManager.MemoryInfo` reports. The weights are mapped outside the
 * Java heap, so the app's heap limit says nothing useful here and the
 * device's free memory is what matters.
 *
 * Getting this wrong does not throw an exception. The kernel kills the
 * process, the user sees Memora disappear, and a worker's progress is lost.
 * So the check is deliberately pessimistic.
 */
object MemoryHeadroom {
    /** Error codes, also used by the Dart side to pick a message. */
    const val LOW_RAM_DEVICE = "low_ram_device"
    const val MODEL_TOO_LARGE = "model_too_large"
    const val NOT_ENOUGH_MEMORY = "not_enough_memory"

    /** The kv-cache, the activations and the runtime's own buffers. */
    const val OVERHEAD_FRACTION = 0.3

    /** Floor for the overhead, for small models on cramped devices. */
    const val MIN_OVERHEAD_BYTES = 256L * 1024 * 1024

    /**
     * The most of the device's total memory one model may claim. Free memory
     * right after a reclaim looks better than it is, and the rest of the
     * system still needs to run.
     */
    const val MAX_TOTAL_FRACTION = 0.6

    /** What a [modelBytes] model needs resident while it answers. */
    fun requiredBytes(modelBytes: Long): Long {
        val overhead = maxOf(MIN_OVERHEAD_BYTES, (modelBytes * OVERHEAD_FRACTION).toLong())
        return modelBytes + overhead
    }

    fun decide(
        modelBytes: Long,
        availableBytes: Long,
        totalBytes: Long,
        lowRamDevice: Boolean,
    ): Headroom {
        val required = requiredBytes(modelBytes)
        if (lowRamDevice) {
            return Headroom.Refused(
                LOW_RAM_DEVICE,
                "This device is set up for low memory and can't run a model on board.",
            )
        }
        if (totalBytes > 0 && required > totalBytes * MAX_TOTAL_FRACTION) {
            return Headroom.Refused(
                MODEL_TOO_LARGE,
                "${mb(modelBytes)} MB is too large for a device with ${mb(totalBytes)} MB " +
                    "of memory. Try a smaller model.",
            )
        }
        if (required > availableBytes) {
            return Headroom.Refused(
                NOT_ENOUGH_MEMORY,
                "Loading this model needs about ${mb(required)} MB and only " +
                    "${mb(availableBytes)} MB is free. Close some apps and try again.",
            )
        }
        return Headroom.Allowed
    }

    private fun mb(bytes: Long): Long = bytes / (1024 * 1024)
}
