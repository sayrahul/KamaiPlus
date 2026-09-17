import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release signing credentials live in android/key.properties, which is gitignored.
// When the file is absent (fresh clone, CI, contributor machine) the release build
// falls back to the debug keystore so the project still builds.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

android {
    namespace = "com.kamaiplus.pos"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    defaultConfig {
        applicationId = "com.kamaiplus.pos"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    }

    buildTypes {
        debug {
            // Uses the standard debug keystore that Android Studio / Flutter generate.
        }
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKeystore) "release" else "debug"
            )

            // R8 code shrinking + obfuscation.
            //
            // Both of these were explicitly false, so no shrinking or
            // obfuscation ran at all. Play Console reported "No R8 metadata
            // included", obfuscation 2%, shrinking blank, and warns that
            // percentages under 25% "may impact your visibility and publishing
            // capabilities on Google Play". A 35.6 MB uncompressed DEX was
            // shipping every class of every dependency, used or not.
            //
            // The keep rules in proguard-rules.pro are load-bearing: R8
            // failures surface at RUNTIME, not build time, so read the warning
            // at the top of that file before changing anything here.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Offline Devanagari OCR for the AI-scan fallback.
    //
    // google_mlkit_text_recognition only pulls in the Latin model, so a menu
    // card or parcha printed in Hindi or Marathi produced zero items whenever
    // the cloud scan could not be reached — which is exactly when a merchant
    // on a weak connection needs the fallback. The cloud path reads every
    // Indian language already; this is what happens when it cannot be called.
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")

    // AndroidX Activity for EdgeToEdge backward compatibility (Android 15+ / older Android)
    implementation("androidx.activity:activity:1.9.3")
}
