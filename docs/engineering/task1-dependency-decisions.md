# Task 1 dependency and build decisions — 31 October 2026

The accepted baseline was Flutter 3.47.9 at commit
`c197ca5199e9ee5661e865596c9c07294dfab51c`, Dart 3.13.7, JDK 21.0.13+9,
Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0, SDK 36 and NDK 28.2.13676358.
The historical feasibility spike still describes that baseline.

The owner-authorized root approved a targeted current Kotlin upgrade to **2.4.21**
for [GHSA-r937-wjx7-w2jp](https://github.com/advisories/GHSA-r937-wjx7-w2jp).
The [official Kotlin release list](https://kotlinlang.org/docs/releases.html)
identifies the stable release. The actual Flutter included build declared older
Kotlin JVM/plugin dependencies, so changing only the app plugin was insufficient.
The checked-in wrapper applies `tool/kotlin-security.init.gradle` to app and
included builds, selecting the patched Kotlin plugin family without editing
vendor sources. Actual compiler provenance confirms 2.4.21 in both builds.
Other libraries are not blindly rewritten. Future Compose uses matching 2.4.21.

Gradle 9.3.1 warns that its Kotlin DSL embedding expects 2.2.21. The included
Flutter plugin and app have compiled successfully with the explicit patch;
this is observed compatibility for these builds, not a promise about every
Gradle Kotlin DSL plugin. Build caching is disabled. CI installs a fresh toolchain
and verifies official archive hashes, exact Flutter source/engine, Android JAR,
Gradle distribution and dependency metadata. The same wrapper is used by ordinary
`flutter build apk`; no machine-local init file is required.

Flutter's pinned `integration_test` plugin declares dynamic AndroidX Test ranges
and Guava 28.1-android. The debug runner/core are explicitly aligned with approved
1.7.0 instrumentation pins, and the app graph uses **Guava 33.7.2-android** to
remove known Guava findings, including
[GHSA-xxph-c9ww-hj94](https://github.com/advisories/GHSA-xxph-c9ww-hj94).
The exact graph is locked; Nimbus remains 10.9.1 and Biometric remains 1.1.0.
Official artifact sidecars are checked independently against recorded SHA256
values by `tool/verify_dependency_pins.py`.

APK runtime, instrumentation/test dependencies and build tooling are separate
security scopes. OSV queries disclose only public package coordinates and
versions. The runtime/Pub scanner fails on returned findings or service errors;
it does not claim build tooling, device behavior, or G5 acceptance is clean.
Broad verification metadata contains historical and tool-only artifacts, so an
entry in that metadata alone does not prove an affected library is shipped in
an APK. Independent G5 must assess remaining build-tool findings against the
actual configuration/use. No runtime risk is accepted by a developer report.

The multi-ABI Gradle build and requested ARM64 Flutter build use different engine
artifacts. Both are strictly locked: `android/app/gradle.lockfile` and
`android/app/gradle-arm64.lockfile`. Included-build locks are stored under
`tool/gradle-locks/`. Release signing is explicitly absent; debug signatures are
only development evidence. CI uploads bounded artifacts for seven days and has
no publishing/deployment or untrusted-PR secrets.

## Review fix 1: observed build warnings and ownership

These are successful builds with warnings, not warning-free compatibility
acceptance. The exact diagnostics below are retained from Task 1 evidence
`native-final.log` and `arm64-build.log` in the SDD report directory. ANSI color
escapes and the machine-specific project prefix are omitted here. No toolchain
pin, vendor source, compatibility flag or security policy is changed by this fix.

- Gradle's included Flutter tooling reports: `WARNING: Unsupported Kotlin plugin
  version.` and `The `embedded-kotlin` and `kotlin-dsl` plugins rely on features
  of Kotlin `2.2.21` that might work differently than in the requested version
  `2.4.21`.` It also says `Using the `kotlin-dsl` plugin together with a different
  Kotlin version (for example, by using the Kotlin Gradle plugin (`kotlin(jvm)`))
  in the same project is not recommended.` Owner: the mobile build maintainer,
  coordinating the Gradle/Flutter included-build compatibility boundary. The
  targeted security override stays in place; successful compilation does not
  establish compatibility with every Kotlin DSL feature.
- AGP reports `WARNING: The option setting 'android.builtInKotlin=false' is
  deprecated.` and `WARNING: The option setting 'android.newDsl=false' is
  deprecated.` For each: `The current default is 'true'.` and `It will be removed
  in version 10.0 of the Android Gradle plugin.` Kotlin also reports
  `Deprecated 'org.jetbrains.kotlin.android' plugin usage` for `:app` and
  `:integration_test`, saying that the plugin `is no longer required for Kotlin
  support since AGP 9.0.` Owner: the mobile build maintainer for app settings;
  upstream Flutter for the integration plugin. Resolve the built-in Kotlin/new
  DSL migration together in the next deliberately tested toolchain update,
  including the security override's actual selected graph.
- Flutter reports `WARNING: Your Android app project: app located at:` the app
  `android/app/build.gradle.kts`, followed by `applies the Kotlin Gradle Plugin,
  which will cause build failures in future versions of Flutter.` and
  `Please migrate your app to Built-in Kotlin using this guide:`
  <https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers>.
  Owner: the mobile build maintainer at the Flutter/AGP compatibility boundary.
  The current pinned build succeeds; future Flutter support is not established.
- Both native and ordinary Flutter assembly report `Warning: SDK processing.
  This version only understands SDK XML versions up to 3 but an SDK XML file of
  version 4 was encountered. This can happen if you use versions of Android
  Studio and the command-line tools that were released at different times.`
  Owner: the mobile toolchain maintainer. This is an SDK metadata reader/writer
  compatibility warning, not proof of an APK runtime failure; exact emitting
  dependency attribution remains for that update. SDK/platform hashes and the
  observed build remain recorded; do not suppress the warning or infer fresh-CI
  acceptance.
- The included Flutter compiler reports `The argument '-Xuse-fir-lt' is
  deprecated since Kotlin 2.4.20. It will be removed in one of the future
  releases. The light tree mode is enabled by default, and it will become the
  only available mode in one of the future releases.` `Deeplink.kt` lines
  13/15/17/19 report `This annotation is currently applied to the value parameter
  only, but in the future it will also be applied to property.` `FlutterPlugin.kt`
  lines 12/664 report `'interface ApkVariant : Any, BaseVariant,
  InstallableVariant, AndroidArtifactVariant, InternalBaseVariant' is deprecated.
  Deprecated in Java.` `FlutterPluginUtils.kt:766` reports `Condition is always
  'true'.` `PluginHandler.kt:168/169` reports `Unchecked cast of
  'NamedDomainObjectContainer<out BuildType>' to
  'NamedDomainObjectContainer<BuildType>'.` Owner: upstream Flutter build tooling;
  the mobile build maintainer must retest the replacement toolchain. Pinned
  vendor source remains unchanged.
- Gradle ends with `Deprecated Gradle features were used in this build, making
  it incompatible with Gradle 10.` This summary does not identify every owning
  plugin. Owner: the mobile build maintainer to inventory with `--warning-mode
  all` during the planned compatibility update before advancing Gradle. It is
  not an authorization to upgrade Gradle in this product correction.

These build-time compatibility diagnostics are separate from APK runtime/Pub
vulnerability results, instrumentation results and independent G5 applicability.
Real-device and clean remote-CI checks remain pending.
