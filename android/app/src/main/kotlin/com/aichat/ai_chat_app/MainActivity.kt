package com.aichat.ai_chat_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * AI Chat — Android native layer.
 *
 * Responsibilities:
 *  1. Secure storage for the OpenRouter API key (EncryptedSharedPreferences,
 *     backed by Android Keystore).
 *  2. General app settings (selected model, system prompt, theme).
 *  3. Bridge into the C++/NDK layer (JNI) for SHA-256 fingerprinting and
 *     native message-ID generation.
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "com.aichat.app/native"
        private const val PREFS_FILE = "ai_chat_secure_prefs"
        private const val KEY_API = "openrouter_api_key"
        private const val PREFIX_SETTING = "setting_"
    }

    // ---------- JNI bridge into C++ (android/app/src/main/cpp) ----------
    private external fun jniSha256Hex(input: String): String
    private external fun jniNextMessageId(): Long

    private var _mediaPlayer: android.media.MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Load the C++ library built by CMake.
        System.loadLibrary("ai_chat_native")
        setupChannel(flutterEngine)
    }

    private fun securePrefs(context: Context): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context,
            PREFS_FILE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    private fun setupChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "saveApiKey" -> {
                            val key = call.argument<String>("key") ?: ""
                            securePrefs(applicationContext).edit()
                                .putString(KEY_API, key).apply()
                            result.success(null)
                        }
                        "getApiKey" -> {
                            val key = securePrefs(applicationContext).getString(KEY_API, "")
                            result.success(key ?: "")
                        }
                        "deleteApiKey" -> {
                            securePrefs(applicationContext).edit()
                                .remove(KEY_API).apply()
                            result.success(null)
                        }
                        "saveSetting" -> {
                            val name = call.argument<String>("name") ?: "unknown"
                            val value = call.argument<String>("value") ?: ""
                            securePrefs(applicationContext).edit()
                                .putString(PREFIX_SETTING + name, value).apply()
                            result.success(null)
                        }
                        "getSetting" -> {
                            val name = call.argument<String>("name") ?: "unknown"
                            val value = securePrefs(applicationContext)
                                .getString(PREFIX_SETTING + name, "")
                            result.success(value ?: "")
                        }
                        "nativeSha256" -> {
                            val input = call.argument<String>("input") ?: ""
                            result.success(jniSha256Hex(input))
                        }
                        "nativeMessageId" -> {
                            result.success(jniNextMessageId())
                        }
                        "checkAudioPermission" -> {
                            val ok = android.os.Build.VERSION.SDK_INT < 23 ||
                                checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
                                    android.content.pm.PackageManager.PERMISSION_GRANTED
                            result.success(ok)
                        }
                        "requestAudioPermission" -> {
                            if (android.os.Build.VERSION.SDK_INT >= 23 &&
                                checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
                                    android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), 1001)
                                result.success(false)
                            } else {
                                result.success(true)
                            }
                        }
                        "playAudio" -> {
                            val path = call.argument<String>("path") ?: ""
                            try {
                                _mediaPlayer?.release()
                                _mediaPlayer = android.media.MediaPlayer().apply {
                                    setDataSource(path)
                                    prepare()
                                    setOnCompletionListener {
                                        try {
                                            release()
                                        } catch (_: Exception) {
                                        }
                                    }
                                    start()
                                }
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                        "stopAudio" -> {
                            try {
                                _mediaPlayer?.stop()
                                _mediaPlayer?.release()
                            } catch (_: Exception) {
                            }
                            _mediaPlayer = null
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    result.error("NATIVE_ERROR", e.message, null)
                }
            }
    }
}
