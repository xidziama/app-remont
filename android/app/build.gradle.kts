import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services plugin reads android/app/google-services.json and generates
    // Android resources with Firebase project id, app id and API key. Without it
    // Firebase Auth may start with stale placeholder values from Dart options.
    id("com.google.gms.google-services")
}

// android/key.properties хранит пароли релизного keystore и не попадает в git
// (см. android/.gitignore). На машине без этого файла debug-сборка должна
// продолжать работать как обычно.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Gradle конфигурирует DSL-блок buildTypes.release при ЛЮБОЙ сборке (в том числе
// debug), поэтому падать с ошибкой из-за отсутствия key.properties можно только
// если реально запрошена release-задача — иначе сломаем обычный `flutter run`.
val isReleaseTaskRequested = gradle.startParameter.taskNames.any { it.contains("Release") }

android {
    namespace = "com.remont.app"
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
        applicationId = "com.remont.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            } else if (isReleaseTaskRequested) {
                throw GradleException(
                    "Release signing не настроен: создайте android/key.properties " +
                        "(storePassword/keyPassword/keyAlias/storeFile) перед сборкой release. " +
                        "Без него release-сборка не будет подписана боевым ключом."
                )
            }
            // Иначе (debug-сборка без key.properties) конфиг просто не используется.
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Сюда попадаем только когда release-задача НЕ запрошена
                // (см. throw выше) — конфигурация debug-сборки не должна падать.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
