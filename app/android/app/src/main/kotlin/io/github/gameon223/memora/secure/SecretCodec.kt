package io.github.gameon223.memora.secure

import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** An encrypted value and the IV it was sealed with. */
class Sealed(val iv: ByteArray, val ciphertext: ByteArray) {
    override fun equals(other: Any?): Boolean =
        other is Sealed && iv.contentEquals(other.iv) && ciphertext.contentEquals(other.ciphertext)

    override fun hashCode(): Int = 31 * iv.contentHashCode() + ciphertext.contentHashCode()
}

/** Stored form of a secret: `base64(iv):base64(ciphertext)`. */
object SecretCodec {
    private const val SEPARATOR = ':'

    fun encode(sealed: Sealed): String {
        val encoder = Base64.getEncoder()
        return encoder.encodeToString(sealed.iv) + SEPARATOR + encoder.encodeToString(sealed.ciphertext)
    }

    /** Returns null for anything that isn't a well-formed stored value. */
    fun decode(stored: String): Sealed? {
        val parts = stored.split(SEPARATOR)
        if (parts.size != 2 || parts[0].isEmpty() || parts[1].isEmpty()) return null
        return try {
            val decoder = Base64.getDecoder()
            val iv = decoder.decode(parts[0])
            val ciphertext = decoder.decode(parts[1])
            if (iv.size != AesGcm.IV_BYTES || ciphertext.size < AesGcm.TAG_BITS / 8) null
            else Sealed(iv, ciphertext)
        } catch (ignored: IllegalArgumentException) {
            null
        }
    }
}

/**
 * AES-GCM with a fresh random IV for every value. The secret's name is bound
 * as associated data, so a ciphertext copied under another name won't open.
 */
object AesGcm {
    const val TRANSFORMATION = "AES/GCM/NoPadding"
    const val IV_BYTES = 12
    const val TAG_BITS = 128

    fun seal(key: SecretKey, plaintext: ByteArray, associatedData: ByteArray): Sealed {
        // No IV is passed in: the provider generates a random one. Android
        // Keystore keys require this.
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(associatedData)
        val ciphertext = cipher.doFinal(plaintext)
        val iv = cipher.iv
        check(iv != null && iv.size == IV_BYTES) { "Unexpected IV length" }
        return Sealed(iv, ciphertext)
    }

    fun open(key: SecretKey, sealed: Sealed, associatedData: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, sealed.iv))
        cipher.updateAAD(associatedData)
        return cipher.doFinal(sealed.ciphertext)
    }
}
