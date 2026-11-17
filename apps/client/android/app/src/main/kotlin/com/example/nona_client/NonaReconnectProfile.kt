package com.example.nona_client

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** The last working profile, encrypted for this installation's Android Keystore. */
internal object NonaReconnectProfile {
    private const val alias = "nona_vpn_reconnect_v1"
    private const val preferences = "nona_vpn_reconnect"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build())
        return generator.generateKey()
    }

    @Synchronized fun save(context: Context, profile: String) {
        require(profile.length in 1..(1 shl 20))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encoded = Base64.encodeToString(cipher.iv + cipher.doFinal(profile.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        check(context.getSharedPreferences(preferences, Context.MODE_PRIVATE).edit()
            .putString("profile", encoded).commit())
    }

    @Synchronized fun load(context: Context): String? {
        val encoded = context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
            .getString("profile", null) ?: return null
        return try {
            val bytes = Base64.decode(encoded, Base64.DEFAULT)
            require(bytes.size >= 29 && bytes.size <= (1 shl 20) + 28)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
        } catch (_: Exception) {
            context.getSharedPreferences(preferences, Context.MODE_PRIVATE).edit().remove("profile").commit()
            null
        }
    }

    @Synchronized fun clear(context: Context) {
        context.getSharedPreferences(preferences, Context.MODE_PRIVATE).edit().clear().commit()
        try { KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(alias) }
        catch (_: Exception) { }
    }
}
