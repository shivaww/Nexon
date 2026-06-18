plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Read version from pubspec.yaml
def pubspecFile = file("../../pubspec.yaml")
def pubspecContent = pubspecFile.exists() ? pubspecFile.text : "version: 1.0.0+1"
def versionMatch = (pubspecContent =~ /version:\s*(\d+\.\d+\.\d+)\+(\d+)/)
def pubspecVersion = versionMatch ? versionMatch[0][1] : "1.0.0"
def pubspecBuild = versionMatch ? versionMatch[0][2].toInteger() : 1

android {
    namespace = "com.termuxforge.app"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.termuxforge.app"
        minSdk = 24
        targetSdk = 35
        versionCode = pubspecBuild
        versionName = pubspecVersion
        multiDexEnabled = true
    }

    // Release signing configuration
    signingConfigs {
        create("release") {
            // Use environment variables for CI/CD signing
            val keystorePath = System.getenv("KEYSTORE_PATH")
            val keystorePassword = System.getenv("KEYSTORE_PASSWORD")
            val keyAlias = System.getenv("KEY_ALIAS")
            val keyPassword = System.getenv("KEY_PASSWORD")

            if (keystorePath != null && file(keystorePath).exists()) {
                storeFile = file(keystorePath)
                storePassword = keystorePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }

        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Use release signing if available, otherwise debug
            val releaseConfig = signingConfigs.findByName("release")
            signingConfig = if (releaseConfig?.storeFile != null) {
                releaseConfig
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    // Disable Compose (Flutter handles UI)
    buildFeatures {
        compose = false
        buildConfig = true
    }

    lint {
        disable += "InvalidPackage"
        checkReleaseBuilds = false
    }
}

flutter {
    source = "../.."
}
