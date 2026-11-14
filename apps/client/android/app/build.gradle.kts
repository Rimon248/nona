plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStoreFile = providers.environmentVariable("NONA_ANDROID_KEYSTORE_PATH").orNull
val releaseStorePassword = providers.environmentVariable("NONA_ANDROID_STORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("NONA_ANDROID_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("NONA_ANDROID_KEY_PASSWORD").orNull
val releaseSigningValues = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val isReleaseRequested = gradle.startParameter.taskNames.any {
    it.substringAfterLast(":").contains("Release", ignoreCase = true)
}
if (isReleaseRequested && releaseSigningValues.any { it.isNullOrBlank() }) {
    throw GradleException(
        "Android release signing is missing. Set NONA_ANDROID_KEYSTORE_PATH, " +
            "NONA_ANDROID_STORE_PASSWORD, NONA_ANDROID_KEY_ALIAS and NONA_ANDROID_KEY_PASSWORD."
    )
}

android {
    namespace = "com.example.nona_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ru.basketref.nona"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        manifestPlaceholders["oidcRedirectScheme"] = "ru.basketref.nona"
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningValues.all { !it.isNullOrBlank() }) {
                storeFile = file(requireNotNull(releaseStoreFile))
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

dependencies {
    implementation(files("libs/libXray.aar"))
    implementation("androidx.core:core:1.15.0")
}
