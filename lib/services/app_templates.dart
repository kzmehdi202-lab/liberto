/// قالب‌های پروژه‌ساز Liberto.
///
/// هر قالب نقشه‌ای است از مسیر فایل -> محتوا با این جای‌گیرها:
///   {{APP_ID}}         مثلاً com.liberto.my_app
///   {{APP_ID_US}}      com_liberto_my_app (برای JNI)
///   {{PKG_PATH}}       com/liberto/my_app
///   {{APP_NAME_SNAKE}} my_app
///   {{LABEL}}          نام نمایشی (فارسی مجاز)
///   {{DESCRIPTION}}    یک خط توضیح

class StackTemplate {
  StackTemplate({
    required this.id,
    required this.title,
    required this.tagline,
    required this.files,
    required this.mainAiPath,
    required this.extraAiPaths,
    required this.aiInstructions,
  });

  final String id;
  final String title;
  final String tagline;
  final Map<String, String> files;
  /// فایلی که هوش مصنوعی حتماً باید بنویسد (شامل {{PKG_PATH}})
  final String mainAiPath;
  /// فایل‌های اضافی که AI می‌نویسد
  final List<String> extraAiPaths;
  final String aiInstructions;
}

String renderTemplate(String content, Map<String, String> vars) {
  var out = content;
  for (final e in vars.entries) {
    out = out.replaceAll('{{${e.key}}}', e.value);
  }
  return out;
}

/// Workflow بیلد پروژه‌های Gradle (Kotlin / Java / C++)
const String _gradleWorkflow = '''name: Build Android APK
on:
  push:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
      - uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: 9.3.1
      - name: Build debug APK
        run: gradle :app:assembleDebug --no-daemon
      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: app
          path: app/build/outputs/apk/debug/app-debug.apk
''';

/// Workflow بیلد پروژه C++/NDK (با نصب NDK و CMake)
const String _ndkWorkflow = '''name: Build Android APK
on:
  push:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
      - uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: 9.3.1
      - name: Install NDK and CMake
        run: |
          yes | sdkmanager --licenses || true
          sdkmanager "cmake;3.22.1" "ndk;27.2.12479018" || true
      - name: Build debug APK
        run: gradle :app:assembleDebug --no-daemon
      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: app
          path: app/build/outputs/apk/debug/app-debug.apk
''';

/// Workflow بیلد پروژه Flutter
const String _flutterWorkflow = '''name: Build Flutter APK
on:
  push:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter config --no-analytics
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: app
          path: build/app/outputs/flutter-apk/app-release.apk
''';

const String _gitignore = '''.gradle/
build/
local.properties
*.iml
.idea/
.dart_tool/
.DS_Store
''';

String _readme() => '''# {{LABEL}}

{{DESCRIPTION}}

Build with **Liberto** — سازنده‌ی هوشمند اپ‌های اندروید.
''';

const String _commonRules = '''Respond with ONLY one valid JSON object. No markdown fences, no explanations, no text before or after the JSON.
JSON shape:
{"app_name":"<1-3 English words>","label":"<short name, Persian allowed>","description":"<one short English sentence>","files":[{"path":"<exact path>","content":"<FULL file content>"}]}
HARD RULES:
1. The "files" array must contain EXACTLY the required paths listed below, no more, no less.
2. Every file must be COMPLETE and COMPILABLE. Never write TODO, "..." , "rest of the code", or placeholders.
3. Implement EXACTLY what the user described, fully working, clean modern UI.
4. All user-visible text in the UI must be Persian (Farsi), RTL-friendly.
5. Escape JSON strings correctly (\\n for newlines).
''';

const String _kotlinRules = '''REQUIRED PATHS: app/src/main/java/{{PKG_PATH}}/MainActivity.kt
STACK RULES:
6. The Kotlin file must start with `package {{APP_ID}};`. One class `MainActivity : AppCompatActivity`.
7. Build the entire UI programmatically (no XML layout files, no res/ files).
8. Allowed libraries: androidx.core:core-ktx, androidx.appcompat, com.google.android.material and Kotlin stdlib ONLY.
9. The app must launch and work immediately without any setup.
''';

const String _javaRules = '''REQUIRED PATHS: app/src/main/java/{{PKG_PATH}}/MainActivity.java
STACK RULES:
6. The Java file must start with `package {{APP_ID}};`. One class `MainActivity extends AppCompatActivity`.
7. Build the entire UI programmatically (no XML layout files, no res/ files).
8. Allowed libraries: androidx.appcompat, com.google.android.material and java stdlib ONLY (no Kotlin).
9. The app must launch and work immediately without any setup.
''';

const String _cppRules = '''REQUIRED PATHS: app/src/main/cpp/native-lib.cpp AND app/src/main/java/{{PKG_PATH}}/MainActivity.kt
STACK RULES:
6. native-lib.cpp must contain (a) your real C++ core logic in a function `std::string liberto_core(const std::string& input)`, and (b) EXACTLY this JNI registration (do not modify it):
extern "C" {
jstring nativeLogicImpl(JNIEnv* env, jclass, jstring input) {
    const char* in = env->GetStringUTFChars(input, nullptr);
    std::string out = liberto_core(in);
    env->ReleaseStringUTFChars(input, in);
    return env->NewStringUTF(out.c_str());
}
}
static JNINativeMethod methods[] = {
    {"nativeLogic", "(Ljava/lang/String;)Ljava/lang/String;", (void*)nativeLogicImpl},
};
extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void*) {
    JNIEnv* env = nullptr;
    if (vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    jclass clazz = env->FindClass("{{APP_ID_US}}/MainActivity");
    if (clazz && env->RegisterNatives(clazz, methods, 1) != JNI_OK) return JNI_ERR;
    return JNI_VERSION_1_6;
}
#include <jni.h> and #include <string> at the top.
7. MainActivity.kt: `package {{APP_ID}};`, class `MainActivity : AppCompatActivity`, declares `private external fun nativeLogic(input: String): String`, loads `System.loadLibrary("liberto_native")` in a companion/init, builds the UI programmatically (no XML), and uses nativeLogic() so the C++ core does the app's real work.
8. Allowed: androidx.core:core-ktx, androidx.appcompat, com.google.android.material, kotlin stdlib ONLY.
''';

const String _flutterRules = '''REQUIRED PATHS: lib/main.dart
STACK RULES:
6. lib/main.dart must be a COMPLETE Flutter app: main() + widgets, Material 3 (useMaterial3: true).
7. External packages are FORBIDDEN — Flutter SDK only.
8. Everything in this single file. The app must launch and work immediately.
''';

Map<String, StackTemplate> buildTemplates() {
  final kotlinFiles = <String, String>{
    'settings.gradle.kts': '''pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "{{APP_NAME_SNAKE}}"
include(":app")
''',
    'build.gradle.kts': '''allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
''',
    'gradle.properties': '''org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
''',
    'app/build.gradle.kts': '''plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "{{APP_ID}}"
    compileSdk = 36

    defaultConfig {
        applicationId = "{{APP_ID}}"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
''',
    'app/src/main/AndroidManifest.xml': '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="{{LABEL}}"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
''',
    '.github/workflows/build-android.yml': _gradleWorkflow,
    '.gitignore': _gitignore,
    'README.md': _readme(),
  };

  final javaFiles = Map<String, String>.from(kotlinFiles);
  javaFiles['settings.gradle.kts'] = '''pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("com.android.application") version "9.1.0" apply false
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "{{APP_NAME_SNAKE}}"
include(":app")
''';
  javaFiles['app/build.gradle.kts'] = '''plugins {
    id("com.android.application")
}

android {
    namespace = "{{APP_ID}}"
    compileSdk = 36

    defaultConfig {
        applicationId = "{{APP_ID}}"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
''';

  final cppFiles = Map<String, String>.from(kotlinFiles);
  cppFiles['.github/workflows/build-android.yml'] = _ndkWorkflow;
  cppFiles['app/build.gradle.kts'] = '''plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "{{APP_ID}}"
    compileSdk = 36
    ndkVersion = "27.2.12479018"

    defaultConfig {
        applicationId = "{{APP_ID}}"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
''';
  cppFiles['app/src/main/cpp/CMakeLists.txt'] = '''cmake_minimum_required(VERSION 3.22.1)
project("liberto_native")

add_library(liberto_native SHARED native-lib.cpp)

find_library(log-lib log)
target_link_libraries(liberto_native \${log-lib})
''';

  final flutterFiles = <String, String>{
    'pubspec.yaml': '''name: {{APP_NAME_SNAKE}}
description: {{DESCRIPTION}}
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

flutter:
  uses-material-design: true
''',
    '.github/workflows/build-android.yml': _flutterWorkflow,
    '.gitignore': _gitignore,
    'README.md': _readme(),
    'android/settings.gradle.kts': '''pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("\$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
''',
    'android/build.gradle.kts': '''allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
''',
    'android/gradle.properties': '''org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
kotlin.daemon.jvmargs=-Xmx1024m -XX:MaxMetaspaceSize=384m
android.useAndroidX=true
android.newDsl=false
android.builtInKotlin=false
''',
    'android/app/build.gradle.kts': '''plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "{{APP_ID}}"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "{{APP_ID}}"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
''',
    'android/app/src/main/AndroidManifest.xml': '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="{{LABEL}}"
        android:name="\${applicationName}">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme"
                />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
''',
    'android/app/src/main/kotlin/{{PKG_PATH}}/MainActivity.kt': '''package {{APP_ID}}

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
''',
    'android/app/src/main/res/values/styles.xml': '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@android:color/white</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@android:color/white</item>
    </style>
</resources>
''',
  };

  return {
    'kotlin': StackTemplate(
      id: 'kotlin',
      title: 'اندروید نیتیو (Kotlin)',
      tagline: 'اولویت اصلی — اپ بومی اندروید با کاتلین',
      files: kotlinFiles,
      mainAiPath: 'app/src/main/java/{{PKG_PATH}}/MainActivity.kt',
      extraAiPaths: const [],
      aiInstructions: _commonRules + _kotlinRules,
    ),
    'java': StackTemplate(
      id: 'java',
      title: 'اندروید نیتیو (Java)',
      tagline: 'اپ بومی اندروید با جاوا',
      files: javaFiles,
      mainAiPath: 'app/src/main/java/{{PKG_PATH}}/MainActivity.java',
      extraAiPaths: const [],
      aiInstructions: _commonRules + _javaRules,
    ),
    'cpp': StackTemplate(
      id: 'cpp',
      title: 'C++ (NDK)',
      tagline: 'هسته‌ی C++ نیتیو + رابط کاتلین',
      files: cppFiles,
      mainAiPath: 'app/src/main/java/{{PKG_PATH}}/MainActivity.kt',
      extraAiPaths: const ['app/src/main/cpp/native-lib.cpp'],
      aiInstructions: _commonRules + _cppRules,
    ),
    'flutter': StackTemplate(
      id: 'flutter',
      title: 'Flutter',
      tagline: 'اپ چندبافتاری با فلوتر',
      files: flutterFiles,
      mainAiPath: 'lib/main.dart',
      extraAiPaths: const [],
      aiInstructions: _commonRules + _flutterRules,
    ),
  };
}
