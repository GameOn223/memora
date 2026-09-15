package io.github.gameon223.memora.secure

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.github.gameon223.memora.bridge.SecretHostApi
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * API keys encrypted with AES-256-GCM under a non-exportable Android
 * Keystore key, stored in app-private preferences that are excluded from
 * backups. Values are never logged.
 */
class KeystoreSecretStore private constructor(context: Context) : SecretHostApi {
    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override fun read(key: String): String? {
        val stored = prefs.getString(key, null) ?: return null
        val sealed = SecretCodec.decode(stored) ?: return null
        return try {
            String(AesGcm.open(secretKey(), sealed, key.toByteArray(Charsets.UTF_8)), Charsets.UTF_8)
        } catch (ignored: GeneralSecurityException) {
            // The Keystore key was replaced, for example after a device
            // restore. The user has to enter the key again.
            null
        }
    }

    override fun write(key: String, value: String) {
        val sealed = AesGcm.seal(
            secretKey(),
            value.toByteArray(Charsets.UTF_8),
            key.toByteArray(Charsets.UTF_8),
        )
        prefs.edit().putString(key, SecretCodec.encode(sealed)).apply()
    }

    override fun delete(key: String) {
        prefs.edit().remove(key).apply()
    }

    override fun keys(): List<String> = prefs.all.keys.sorted()

    @Synchronized
    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    companion object {
        const val PREFS_NAME = "memora_secrets"
        const val KEY_ALIAS = "memora_secrets"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"

        @Volatile
        private var instance: KeystoreSecretStore? = null

        fun get(context: Context): KeystoreSecretStore =
            instance ?: synchronized(this) {
                instance ?: KeystoreSecretStore(context.applicationContext).also { instance = it }
            }
    }
}
