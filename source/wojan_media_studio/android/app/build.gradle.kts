import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProps = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.exists()) FileInputStream(keyFile).use { stream -> keyProps.load(stream) }
fun prop(k: String, env: String): String? = keyProps.getProperty(k) ?: System.getenv(env)
val storePath: String? = prop("storeFile", "WMS_KEYSTORE_PATH")

android {
    namespace = "pl.wojan.mediastudio"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Stable application id – NEVER change (updates must keep id + signing key).
        applicationId = "pl.wojan.mediastudio"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing: key.properties (local, git-ignored) or CI env vars.
    signingConfigs {
        if (storePath != null) {
            create("release") {
                storeFile = file(storePath)
                storePassword = prop("storePassword", "WMS_KEYSTORE_PASSWORD")
                keyAlias = prop("keyAlias", "WMS_KEY_ALIAS")
                keyPassword = prop("keyPassword", "WMS_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (storePath != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        jniLibs { useLegacyPackaging = true }
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

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
}
