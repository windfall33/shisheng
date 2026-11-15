import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 签名口令放在 app/android/key.properties（不进仓库）。
// 没有这个文件，release 构建会直接失败并告诉你怎么办——不要偷偷退回 debug 签名，
// 那样打出来的包换个机器就装不上、也升不了级。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "app.shisheng.shisheng_reader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.shisheng.shisheng_reader"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// 没配置签名时，release 会在打包阶段报「SigningConfig "release" is missing required
// property storeFile」，这里提前把它翻译成人话。
gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.name.contains("Release") && it.project == project }
    if (wantsRelease && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "缺少 app/android/key.properties。\n" +
                "复制 key.properties.example 为 key.properties，或按 README 里那行 keytool 命令" +
                "生成自己的签名密钥，再把路径和口令填进去。\n" +
                "只想自己装着玩的话，也可以用 flutter build apk --debug。"
        )
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
