package io.github.gameon223.memora.gallery

import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

/** Parses EXIF date strings such as `2026:08:14 09:30:05`. */
object ExifDates {
    private val FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ss")

    /**
     * Epoch millis for an EXIF `DateTimeOriginal`. Uses [offset] (EXIF
     * `OffsetTimeOriginal`, for example `+05:30`) when present, else [zone].
     * Returns null for blank, zeroed or malformed values.
     */
    fun parse(dateTime: String?, offset: String?, zone: ZoneId): Long? {
        val raw = dateTime?.trim().orEmpty()
        if (raw.length < 19) return null
        var value = raw.substring(0, 19)
        // Some writers use dashes in the date part.
        if (value[4] == '-' && value[7] == '-') {
            value = value.substring(0, 4) + ':' + value.substring(5, 7) + ':' + value.substring(8)
        }
        if (value.startsWith("0000")) return null
        val local = try {
            LocalDateTime.parse(value, FORMAT)
        } catch (error: DateTimeParseException) {
            return null
        }
        val zoneOffset = offset?.trim()?.takeIf { it.isNotEmpty() }?.let {
            try {
                ZoneOffset.of(it)
            } catch (error: java.time.DateTimeException) {
                null
            }
        }
        return if (zoneOffset != null) {
            local.toInstant(zoneOffset).toEpochMilli()
        } else {
            local.atZone(zone).toInstant().toEpochMilli()
        }
    }
}

/**
 * Picks the filing date for an image, in the order from
 * docs/architecture.md 4.1: MediaStore `DATE_TAKEN`, then EXIF
 * `DateTimeOriginal`, then the file's modified time, then now.
 */
object TakenTime {
    fun choose(mediaStoreTaken: Long?, exifTaken: Long?, modified: Long?, now: Long): Long =
        listOf(mediaStoreTaken, exifTaken, modified).firstOrNull { it != null && it > 0 } ?: now
}
