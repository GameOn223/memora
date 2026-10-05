package io.github.gameon223.memora.inference.llm

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GenerationTurnsTest {
    @Test
    fun idsStartAtOneAndCountUp() {
        val turns = GenerationTurns()

        val first = turns.begin()
        turns.end(first)
        val second = turns.begin()

        assertEquals(1L, first)
        assertEquals(2L, second)
    }

    @Test
    fun aSecondGenerationIsRefusedWhileOneRuns() {
        val turns = GenerationTurns()
        val running = turns.begin()

        val error = try {
            turns.begin()
            null
        } catch (error: GenerationBusyException) {
            error
        }

        assertEquals(running, error?.runningId)
        assertEquals(running, turns.runningId)
    }

    @Test
    fun aRefusedGenerationDoesNotConsumeAnId() {
        val turns = GenerationTurns()
        val first = turns.begin()
        try {
            turns.begin()
        } catch (error: GenerationBusyException) {
            // Expected.
        }
        turns.end(first)

        assertEquals(2L, turns.begin())
    }

    @Test
    fun endingClearsTheTurn() {
        val turns = GenerationTurns()
        val id = turns.begin()

        assertTrue(turns.end(id))
        assertNull(turns.runningId)
    }

    @Test
    fun aLateFinishCannotReleaseSomeoneElsesTurn() {
        val turns = GenerationTurns()
        val first = turns.begin()
        turns.end(first)
        val second = turns.begin()

        assertFalse(turns.end(first))
        assertEquals(second, turns.runningId)
    }

    @Test
    fun cancellingTheRunningRequestIsAcceptedOnce() {
        val turns = GenerationTurns()
        val id = turns.begin()

        assertTrue(turns.cancel(id))
        assertTrue(turns.isCancelled(id))
    }

    @Test
    fun cancellingAnUnknownRequestIsIgnored() {
        val turns = GenerationTurns()
        val id = turns.begin()

        assertFalse(turns.cancel(id + 1))
        assertFalse(turns.cancel(0))
        assertFalse(turns.isCancelled(id))
    }

    @Test
    fun cancellingAFinishedRequestIsIgnored() {
        val turns = GenerationTurns()
        val id = turns.begin()
        turns.end(id)

        assertFalse(turns.cancel(id))
        assertFalse(turns.isCancelled(id))
    }

    @Test
    fun aNewTurnIsNotBornCancelled() {
        val turns = GenerationTurns()
        val first = turns.begin()
        turns.cancel(first)
        turns.end(first)
        val second = turns.begin()

        assertFalse(turns.isCancelled(second))
    }

    @Test
    fun onlyOneOfManyThreadsGetsTheTurn() {
        val turns = GenerationTurns()
        val threads = 16
        val pool = Executors.newFixedThreadPool(threads)
        val start = CountDownLatch(1)
        val done = CountDownLatch(threads)
        val ids = java.util.Collections.synchronizedList(mutableListOf<Long>())

        repeat(threads) {
            pool.execute {
                start.await()
                try {
                    ids.add(turns.begin())
                } catch (error: GenerationBusyException) {
                    // Expected for all but one.
                } finally {
                    done.countDown()
                }
            }
        }
        start.countDown()
        assertTrue(done.await(10, TimeUnit.SECONDS))
        pool.shutdown()

        assertEquals(listOf(1L), ids.toList())
    }
}
