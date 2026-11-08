plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ir.locstore.locstore"
    compileSdk = flutter.compileSdkVersion
    // Pinned so the Flutter tool marks the NDK as installed and skips the
    // synthetic CMake step it uses to force an NDK download. The NDK on this
    // build machine is a minimal skeleton: this app and all its plugins are
    // pure Java/Kotlin, and the engine .so libraries ship pre-stripped — the
    // only NDK use here is the symbol-strip pass (llvm-strip shim).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ir.locstore.locstore"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Stable app identity: a single keystore, committed with the project and
    // shared by debug & release builds, so every rebuild (any machine, any
    // CI) signs with the SAME key. Android refuses to update-install an APK
    // whose signature differs from the installed app — the old template
    // default (~/.android/debug.keystore) changed on every build machine,
    // which is why previous updates showed "App not installed".
    signingConfigs {
        create("locstore") {
            storeFile = rootProject.file("locstore.keystore")
            storePassword = "locstore-signing"
            keyAlias = "locstore"
            // PKCS12 keystores use the store password for keys as well.
            keyPassword = "locstore-signing"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("locstore")
        }
        debug {
            signingConfig = signingConfigs.getByName("locstore")
        }
    }

    lint {
        // Skip lintVitalRelease: it roughly doubles peak memory during
        // release builds and adds nothing for this small offline app (full
        // lint is still available explicitly via `gradlew :app:lint`).
        checkReleaseBuilds = false
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
