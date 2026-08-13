pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// flutter_reactive_ble 5.5.0 declares compileSdk 33 even though its resolved
// AndroidX dependencies require API 34+. Register this before Flutter includes
// plugin projects, then align only that library with our API 36 app SDK.
gradle.beforeProject {
    if (name == "reactive_ble_mobile") {
        afterEvaluate {
            val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
            androidExtension.javaClass
                .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(androidExtension, 36)
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
