import 'dart:io';

import 'package:flutter/services.dart';

/// Bridge to the Android native layer.
///
/// - Kotlin: secure storage for the API key + app settings (MethodChannel)
/// - C++/NDK: SHA-256 key fingerprint + message ID generation (JNI)
class NativeService {
  static const MethodChannel _channel =
      MethodChannel('com.aichat.app/native');

  static bool get isAvailable => Platform.isAndroid;

  // ---------- Secure key storage (Kotlin) ----------

  static Future<void> saveApiKey(String key) async {
    if (!isAvailable) throw UnsupportedError('Android only');
    await _channel.invokeMethod('saveApiKey', {'key': key});
  }

  static Future<String> getApiKey() async {
    if (!isAvailable) return '';
    final v = await _channel.invokeMethod<String>('getApiKey');
    return v ?? '';
  }

  static Future<void> deleteApiKey() async {
    if (!isAvailable) throw UnsupportedError('Android only');
    await _channel.invokeMethod('deleteApiKey');
  }

  // ---------- Settings (Kotlin) ----------

  static Future<void> saveSetting(String name, String value) async {
    if (!isAvailable) return;
    await _channel.invokeMethod('saveSetting', {'name': name, 'value': value});
  }

  static Future<String> getSetting(String name, {String def = ''}) async {
    if (!isAvailable) return def;
    final v = await _channel.invokeMethod<String>('getSetting', {'name': name});
    return (v is String && v.isNotEmpty) ? v : def;
  }

  // ---------- C++ / NDK (JNI) ----------

  /// SHA-256 hex digest computed natively in C++ — used to verify the
  /// stored key without ever exposing the key itself to the UI.
  static Future<String> nativeSha256(String input) async {
    if (!isAvailable) {
      // Fallback: pure-Dart is not available; return placeholder.
      return 'n/a';
    }
    final v =
        await _channel.invokeMethod<String>('nativeSha256', {'input': input});
    return v ?? 'n/a';
  }

  /// Generates a unique message ID natively (time + counter mix in C++).
  static Future<int> nativeMessageId() async {
    if (!isAvailable) {
      return DateTime.now().microsecondsSinceEpoch;
    }
    final v = await _channel.invokeMethod<int>('nativeMessageId');
    return v ?? DateTime.now().microsecondsSinceEpoch;
  }

  // ---------- Audio (voice messages, Kotlin MediaPlayer) ----------

  static Future<bool> hasAudioPermission() async {
    if (!isAvailable) return true;
    return (await _channel.invokeMethod<bool>('checkAudioPermission')) ?? false;
  }

  /// Returns true if already granted; otherwise the system dialog is shown
  /// and you should poll [hasAudioPermission] for a few seconds.
  static Future<bool> requestAudioPermission() async {
    if (!isAvailable) return true;
    return (await _channel.invokeMethod<bool>('requestAudioPermission')) ?? false;
  }

  static Future<bool> playAudio(String path) async {
    if (!isAvailable) return false;
    return (await _channel.invokeMethod<bool>('playAudio', {'path': path})) ?? false;
  }

  static Future<void> stopAudio() async {
    if (!isAvailable) return;
    await _channel.invokeMethod('stopAudio');
  }
}
