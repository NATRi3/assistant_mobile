import java.util.Base64
plugins {
 id("com.android.application")
 id("org.jetbrains.kotlin.android")
 id("dev.flutter.flutter-gradle-plugin")
}
val defines = (project.findProperty("dart-defines") as? String ?: "").split(",").filter { it.isNotEmpty() }.map { String(Base64.getDecoder().decode(it)) }
val origin = defines.singleOrNull { it.startsWith("ASSISTANT_API_ORIGIN=") }?.substringAfter("=") ?: ""
require(origin.matches(Regex("[A-Za-z0-9.:/\\-]*"))) { "Invalid API origin build definition" }
android {
 namespace = "io.github.natri3.assistant"
 compileSdk = 36
 ndkVersion = "28.2.13676358"
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 defaultConfig {
  applicationId = "io.github.natri3.assistant"
  minSdk = 28; targetSdk = 36
  versionCode = flutter.versionCode; versionName = flutter.versionName
  testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
  buildConfigField("String", "ASSISTANT_API_ORIGIN", "\"$origin\"")
 }
 buildFeatures { buildConfig = true }
 buildTypes { release { signingConfig = null } }
 testOptions { unitTests.isReturnDefaultValues = true }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
flutter { source = "../.." }
dependencyLocking {
 lockAllConfigurations()
 // Flutter selects architecture-specific engine artifacts. Keep both supported
 // build graphs frozen; never weaken locking to allow absent engine artifacts.
 if (project.findProperty("target-platform") == "android-arm64") {
  lockFile.set(file("gradle-arm64.lockfile"))
 }
}
dependencies {
 implementation("androidx.biometric:biometric:1.1.0")
 implementation("com.nimbusds:nimbus-jose-jwt:10.9.1")
 // Fix vulnerable transitive Flutter integration_test Guava 28.1 (OSV).
 implementation("com.google.guava:guava:33.7.2-android")
 testImplementation("junit:junit:4.13.2")
 // Align Flutter integration_test runtime to the approved instrumentation pins.
 debugImplementation("androidx.test:runner:1.7.0")
 debugImplementation("androidx.test:core:1.7.0")
 androidTestImplementation("androidx.test:runner:1.7.0")
 androidTestImplementation("androidx.test:core:1.7.0")
 androidTestImplementation("androidx.test.ext:junit:1.3.0")
}
