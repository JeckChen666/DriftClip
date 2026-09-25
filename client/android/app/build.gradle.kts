import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名（ROADMAP P0.3）：优先环境变量（CI 注入 secrets），其次 android/key.properties
// （本地，已被 .gitignore 忽略）。两者都缺失时回退 debug 签名，保证本地 `flutter run --release` 可用。
val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val ksStoreFile = System.getenv("DRIFTCLIP_ANDROID_KEYSTORE_PATH")
    ?: keystoreProps.getProperty("storeFile")
val ksStorePassword = System.getenv("DRIFTCLIP_ANDROID_KEYSTORE_PASSWORD")
    ?: keystoreProps.getProperty("storePassword")
val ksKeyAlias = System.getenv("DRIFTCLIP_ANDROID_KEY_ALIAS")
    ?: keystoreProps.getProperty("keyAlias")
val ksKeyPassword = System.getenv("DRIFTCLIP_ANDROID_KEY_PASSWORD")
    ?: keystoreProps.getProperty("keyPassword")
val releaseSigningAvailable = listOf(ksStoreFile, ksStorePassword, ksKeyAlias, ksKeyPassword)
    .all { !it.isNullOrBlank() } && ksStoreFile?.let { file(it).exists() } == true

android {
    namespace = "com.driftclip.driftclip_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.driftclip.driftclip_client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningAvailable) {
            create("release") {
                storeFile = file(ksStoreFile!!)
                storePassword = ksStorePassword
                keyAlias = ksKeyAlias
                keyPassword = ksKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningAvailable) {
                signingConfigs.getByName("release")
            } else {
                // 未提供正式签名时回退 debug（仅供本地验证；发布必须配置签名，
                // 生成方式见 DEVELOPMENT.md「Android 签名」一节）。
                signingConfigs.getByName("debug")
            }
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
