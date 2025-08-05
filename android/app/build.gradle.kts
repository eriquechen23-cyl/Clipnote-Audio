plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.clipnote_audio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.clipnote_audio"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Copy prebuilt FFmpeg shared libraries into the app's jniLibs
val jniLibsDir = File(projectDir, "src/main/jniLibs")

tasks.register<Copy>("copyFfmpegArm64") {
    from(File(rootDir, "ffmpeg-build/arm64-v8a/libffmpeg.so"))
    into(File(jniLibsDir, "arm64-v8a"))
}

tasks.register<Copy>("copyFfmpegArmv7") {
    from(File(rootDir, "ffmpeg-build/armeabi-v7a/libffmpeg.so"))
    into(File(jniLibsDir, "armeabi-v7a"))
}

tasks.named("preBuild") {
    dependsOn("copyFfmpegArm64", "copyFfmpegArmv7")
}
