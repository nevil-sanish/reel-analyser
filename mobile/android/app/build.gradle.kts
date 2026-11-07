import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing lives outside the repo; key.properties (gitignored) points at it.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "app.reelbrain"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.reelbrain"
        // 29: MediaStore Downloads for Export without a storage permission.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // `full`: every feature, with the optional Accessibility counter, Usage access, notifications and update banner.
    // `semi`: no sensitive permission and no access beyond the internet (see src/semi and lib/flavor.dart).
    flavorDimensions += "dist"
    // The semi build has its own application id and launcher icon, so both can be installed on one phone. The full build keeps
    // `app.reelbrain` (existing installs and their updates). Each has its own notes, keys and settings.
    productFlavors {
        create("full") {
            dimension = "dist"
            manifestPlaceholders["appLabel"] = "Reel Analyser"
        }
        create("semi") {
            dimension = "dist"
            applicationIdSuffix = ".semi"
            manifestPlaceholders["appLabel"] = "Reel Analyser Semi"
        }
    }

    signingConfigs {
        if (keyProps.isNotEmpty()) create("release") {
            storeFile = file(keyProps.getProperty("storeFile"))
            storePassword = keyProps.getProperty("storePassword")
            keyAlias = keyProps.getProperty("keyAlias")
            keyPassword = keyProps.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            // No debug-key fallback: a release without key.properties should fail, not ship debug-signed.
            signingConfig = signingConfigs.findByName("release")
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
