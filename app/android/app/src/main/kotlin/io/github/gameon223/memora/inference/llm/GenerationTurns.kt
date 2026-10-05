package io.github.gameon223.memora.inference.llm

/** Raised when a second generation is asked for while one is running. */
class GenerationBusyException(val runningId: Long) : Exception(
    "A generation is already running. Cancel it before starting another.",
)

/**
 * Hands out request ids and keeps track of the one generation that may be
 * running. The session itself takes one turn at a time, so a second request
 * has to be refused before it reaches the model rather than after.
 *
 * Every method is synchronized. `startGeneration` is answered on the platform
 * thread while the generation runs somewhere else, and a cancel can arrive
 * from either.
 */
class GenerationTurns {
    private var lastId = 0L
    private var running: Long? = null
    private var cancelled: Long? = null

    /** The running request, or null when nothing is running. */
    val runningId: Long? @Synchronized get() = running

    /**
     * Claims the turn and returns a fresh id.
     *
     * @throws GenerationBusyException when a generation is already running.
     */
    @Synchronized
    fun begin(): Long {
        running?.let { throw GenerationBusyException(it) }
        lastId += 1
        running = lastId
        cancelled = null
        return lastId
    }

    /**
     * Releases the turn. Returns false when [id] was not the running one, so
     * a late finish can't release a turn that belongs to someone else.
     */
    @Synchronized
    fun end(id: Long): Boolean {
        if (running != id) return false
        running = null
        return true
    }

    /**
     * Records a cancel. Returns true when [id] is the running request, which
     * is the only case where the model has to be told to stop.
     */
    @Synchronized
    fun cancel(id: Long): Boolean {
        if (running != id) return false
        cancelled = id
        return true
    }

    /** True once [cancel] has accepted [id]. Text after that is dropped. */
    @Synchronized
    fun isCancelled(id: Long): Boolean = cancelled == id
}
