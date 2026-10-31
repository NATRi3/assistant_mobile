# Assistant Mobile

Android-first Flutter client for the personal assistant project.

Implementation and independent acceptance are in progress. No production-ready APK or working push integration is claimed by this initial repository setup.

The implementation branch and pull requests will contain the mobile client, synthetic design artifacts and CI. Runtime credentials, personal data, signing keys and server secrets belong outside this repository.

Project tracking: [AS-80](https://sykhorukov.atlassian.net/browse/AS-80).

The Task 1 app provides owner pairing and a foreground secure session. It starts
unconfigured by default; no API requests, pairing success or assistant data are
simulated. Tasks, chat, push and widgets are later work.

Use the pinned toolchains in `tool/toolchain.lock.json`; Linux CI setup is
`bash tool/bootstrap_ci.sh`. Native Kotlin is 2.4.21 (security patch authorized
against GHSA-r937-wjx7-w2jp); the wrapper applies the checked-in compiler policy
also to Flutter's included Gradle build without editing the SDK. Never bypass
this wrapper or supply a shared/untrusted Gradle build cache.

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
cd android
./gradlew --no-daemon --dependency-verification strict :app:testDebugUnitTest :app:assembleDebug
```

Build an ARM64 development APK with `flutter build apk --debug --target-platform
android-arm64 --no-pub`. A deployment-authorized HTTPS origin can be supplied with
`--dart-define=ASSISTANT_API_ORIGIN=https://your-approved-host`; the same define
builds native and Dart configuration. Do not put tokens, secrets or personal data
in build defines. Release is explicitly unsigned until owner signing is supplied.

The Android tests under `androidTest` require an authorized device and genuine
screen-lock/native authentication. Host tests and APK compilation do not prove
Keystore, biometric, screen-lock removal, backup/transfer, TLS, S25 or Firebase
runtime behavior. These remain separate acceptance evidence. Session/domain
slots are distinct: Task 1 implements encrypted session CAS; domain writes fail
closed until Task 2 implements its authenticated sync-age envelope and writer.

Logout immediately covers the UI, permits only an already-authorized foreground
self-revoke for at most five seconds, then destroys local credentials. Offline or
unconfirmed revocation is clearly shown with the owned public device UUID when
available. Dart immutable strings are not claimed to be physically zeroised.
