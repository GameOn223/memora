import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing reads android/key.properties when it exists. Without it,
// release builds fall back to the debug key so local `flutter run --release`
// still works. See docs/releasing.md.
// MediaPipe LLM Inference. The newest version published for both tasks-genai
// and tasks-core, which do not share every release number.
val mediapipeVersion = "0.10.35"

val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "io.github.gameon223.memora"
    compileSdk = 36
    // Flutter's tested default for this SDK version. Plugins with native
    // code ask for the same one, so a build needs a single NDK.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.gameon223.memora"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ABIs are chosen by the Flutter tool, through --split-per-abi for a
    // release or --target-platform for a one-off build. Setting abiFilters
    // here as well makes Gradle refuse the split build.

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // tasks-core is on the classpath for one reason: the MPImage
            // types the vision path uses to hand a Bitmap to the model.
            // Those are plain Java. Its native library belongs to the
            // graph-based MediaPipe tasks, which Memora never creates.
            // Nothing in tasks-core calls System.loadLibrary, and
            // libllm_inference_engine_jni.so has no DT_NEEDED entry for it,
            // so this is about 10 MB per ABI of code that is never loaded.
            excludes += "**/libmediapipe_tasks_jni.so"
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
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
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.activity:activity-ktx:1.13.0")
    implementation("androidx.fragment:fragment-ktx:1.9.0")
    implementation("androidx.work:work-runtime-ktx:2.12.0")
    implementation("androidx.exifinterface:exifinterface:1.4.2")
    // Bundled Latin model, so OCR works offline from the first launch.
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.30.0")
    // Runs a Gemma model file the user brings in. tasks-core carries the
    // MPImage types the vision path needs; tasks-genai does not bundle them,
    // and the two are kept on the same version on purpose.
    implementation("com.google.mediapipe:tasks-genai:$mediapipeVersion")
    implementation("com.google.mediapipe:tasks-core:$mediapipeVersion")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260814")
}

/**
 * Memora reports nothing about its users. ML Kit brings Google's datatransport
 * library, whose upload backend is removed in the manifest, and a dependency
 * bump could quietly bring it back. Every APK is checked for it.
 */
abstract class VerifyNoTelemetryTask : DefaultTask() {
    @get:InputFile
    abstract val mergedManifest: RegularFileProperty

    @get:OutputFile
    abstract val report: RegularFileProperty

    @TaskAction
    fun verify() {
        val manifest = mergedManifest.get().asFile.readText()
        // The discovery service is how the transport runtime finds a backend
        // to upload through. Without it, events are dropped. The scheduler
        // components it leaves behind have nowhere to send anything.
        val offenders = listOf(
            "com.google.android.datatransport.runtime.backends.TransportBackendDiscovery",
            "CctBackendFactory",
            "com.google.android.datatransport.cct",
        ).filter { manifest.contains(it) }
        if (offenders.isNotEmpty()) {
            throw GradleException(
                "The merged manifest declares a telemetry upload backend: " +
                    offenders.joinToString() +
                    ". A dependency brought Google's datatransport components back. " +
                    "Remove them with tools:node=\"remove\" in app/src/main/AndroidManifest.xml.",
            )
        }
        report.get().asFile.writeText("No telemetry backends in the merged manifest.\n")
    }
}

androidComponents {
    onVariants { variant ->
        val suffix = variant.name.replaceFirstChar { it.uppercase() }
        val verify = tasks.register<VerifyNoTelemetryTask>("verify${suffix}NoTelemetry") {
            mergedManifest.set(
                variant.artifacts.get(com.android.build.api.artifact.SingleArtifact.MERGED_MANIFEST),
            )
            report.set(layout.buildDirectory.file("reports/telemetry/$suffix.txt"))
        }
        // The assemble task doesn't exist yet while variants are created,
        // so match it lazily.
        tasks.matching { it.name == "assemble$suffix" }.configureEach { dependsOn(verify) }
    }
}
