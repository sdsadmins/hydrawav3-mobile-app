import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// A key.properties that EXISTS is not the same as one that is COMPLETE, and the
// difference used to fail the build with "null cannot be cast to non-null type
// kotlin.String" — a missing/misspelled entry read back as null and the `as String`
// cast threw, on `assembleDebug`, which never needed the release keystore at all
// (signingConfigs is evaluated at configuration time regardless of the task).
// Gate on all four values instead, so an incomplete file falls back to debug signing
// the same way a missing one already does.
fun keystoreValue(name: String): String? =
    keystoreProperties.getProperty(name)?.trim()?.takeIf { it.isNotEmpty() }

val releaseSigningReady = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    .all { keystoreValue(it) != null }

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hydrawav3.hydrawav3"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hydrawav3.hydrawav3"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29 // Android 10+ as per PRD requirement
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                keyAlias = keystoreValue("keyAlias")
                keyPassword = keystoreValue("keyPassword")
                storeFile = file(keystoreValue("storeFile")!!)
                storePassword = keystoreValue("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Use the release signing config only when key.properties is present
            // and complete; otherwise fall back to debug signing so local builds work.
            signingConfig = if (releaseSigningReady) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
