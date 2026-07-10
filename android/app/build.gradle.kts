import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase ↔ Google Services. ОБЯЗАТЕЛЬНО подключать здесь, в
    // `plugins { }`, а не условным `apply(plugin = ...)` внизу файла.
    // Плагин цепляется к variant-API AGP и генерирует
    // `app/build/generated/res/processDebugGoogleServices/values/values.xml`
    // со строками `google_app_id`, `gcm_defaultSenderId`, `project_id`
    // — это те самые ключи, которые `Firebase.initializeApp()` читает
    // в рантайме. Если применить плагин ПОСЛЕ блока `android { }`, его
    // variant-хук опаздывает к `mergeResources` и строки в APK не
    // попадают. Симптом — Firebase молча падает в `try/catch`, FCM
    // токен не выдаётся, диалог уведомлений не показывается, а пуш с
    // консоли возвращает «Application install not found».
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// `google-services.json` ОБЯЗАН лежать в android/app/google-services.json
// до запуска сборки. Плагин выше упадёт с понятным сообщением, если
// файла нет — это лучше, чем тихо собрать APK без Firebase-строк.

android {
    namespace = "com.fallrush.fallrushgame"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.fallrush.fallrushgame"
        minSdk = 30
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasKeystore) {
        signingConfigs {
            create("release") {
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
