plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.hoshi.remote"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.hoshi.remote"
        minSdk = 26
        targetSdk = 35
        // Поднимать при каждой новой сборке: по нему приложение узнаёт, что пора обновиться
        // (tools/dev.py android читает его и кладёт в version.json рядом с APK).
        versionCode = 10
        versionName = "0.10"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        buildConfig = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.webkit:webkit:1.12.1")
    // Кнопки плеера на экране блокировки (MediaSession + MediaStyle-уведомление).
    implementation("androidx.media:media:1.7.0")
    // Сканер QR от Google Play: без разрешения на камеру, своё окно съёмки.
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    // WebSocket для фоновой связи с Хоши, когда телефон заблокирован.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
