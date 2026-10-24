# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.

# --- Google Tink (used by androidx security-crypto for encrypted prefs) ---
-keep class com.google.crypto.tink.** { *; }
-keepclassmembers class com.google.crypto.tink.** { *; }
# Tink's optional KeysDownloader references these — they are provided as
# implementation deps in build.gradle.kts so R8 full mode sees no gaps.
-dontwarn com.google.api.client.**
-dontwarn org.joda.time.**

# Annotation classes that are compile-time only (safe to ignore if absent)
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn javax.annotation.concurrent.**

# --- AndroidX security ---
-keep class androidx.security.crypto.** { *; }

# --- JNI: native methods in MainActivity (C++ via NDK) ---
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- http package (OpenRouter streaming) ---
-keep class io.netty.** { *; }
-dontwarn io.netty.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
