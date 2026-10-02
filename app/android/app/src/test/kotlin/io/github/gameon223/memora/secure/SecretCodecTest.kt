package io.github.gameon223.memora.secure

import javax.crypto.AEADBadTagException
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SecretCodecTest {
    private val key: SecretKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()

    @Test
    fun encodesAndDecodesStoredValue() {
        val sealed = Sealed(ByteArray(12) { it.toByte() }, ByteArray(20) { (it * 3).toByte() })

        val stored = SecretCodec.encode(sealed)

        assertEquals(1, stored.count { it == ':' })
        assertEquals(sealed, SecretCodec.decode(stored))
    }

    @Test
    fun rejectsMalformedValues() {
        assertNull(SecretCodec.decode(""))
        assertNull(SecretCodec.decode("abc"))
        assertNull(SecretCodec.decode(":"))
        assertNull(SecretCodec.decode("not base64!:also not"))
        // An IV of the wrong length.
        assertNull(SecretCodec.decode("AAAA:AAAAAAAAAAAAAAAAAAAAAA=="))
    }

    @Test
    fun sealsAndOpensWithAssociatedData() {
        val sealed = AesGcm.seal(key, "nvapi-secret".toByteArray(), "provider.nvidia.api_key".toByteArray())

        assertEquals(AesGcm.IV_BYTES, sealed.iv.size)
        val opened = AesGcm.open(key, sealed, "provider.nvidia.api_key".toByteArray())
        assertArrayEquals("nvapi-secret".toByteArray(), opened)
    }

    @Test
    fun usesAFreshIvForEveryValue() {
        val first = AesGcm.seal(key, "same".toByteArray(), "k".toByteArray())
        val second = AesGcm.seal(key, "same".toByteArray(), "k".toByteArray())

        assertFalse(first.iv.contentEquals(second.iv))
        assertFalse(first.ciphertext.contentEquals(second.ciphertext))
    }

    @Test
    fun refusesCiphertextStoredUnderAnotherName() {
        val sealed = AesGcm.seal(key, "value".toByteArray(), "provider.groq.api_key".toByteArray())

        val failed = try {
            AesGcm.open(key, sealed, "provider.openai.api_key".toByteArray())
            false
        } catch (expected: AEADBadTagException) {
            true
        }
        assertTrue(failed)
    }

    @Test
    fun storedValueRoundTripsThroughCipher() {
        val sealed = AesGcm.seal(key, "gsk_live_key".toByteArray(), "name".toByteArray())

        val restored = SecretCodec.decode(SecretCodec.encode(sealed))!!

        assertEquals("gsk_live_key", String(AesGcm.open(key, restored, "name".toByteArray())))
    }
}
