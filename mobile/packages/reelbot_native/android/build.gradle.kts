group = "app.reelbrain"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    // Not "app.reelbrain": that is the app module's namespace, and two modules can't share one.
    namespace = "app.reelbrain.core"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 29
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Same version workmanager_android already puts in the app.
    implementation("androidx.work:work-runtime:2.11.2")
    testImplementation("junit:junit:4.13.2")
    // android.jar's org.json is a stub on the JVM; the fixture tests need the real one.
    testImplementation("org.json:json:20250517")
    // T-CH-01/02: the plugin on a JVM Android runtime, with WorkManager's test setup for the digest it schedules.
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("androidx.test:core:1.7.0")
    testImplementation("androidx.work:work-testing:2.11.2")
}
