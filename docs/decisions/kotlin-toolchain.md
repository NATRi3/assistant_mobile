# Kotlin toolchain correction — AS-86

The initial candidate was Kotlin/Compose2.4.0 from the compiled spike. During Task1 dependency verification GHSA-r937-wjx7-w2jp identified affected Kotlin build-cache deserialization tooling. The coordinator authorized stable2.4.21 for the app and actually used included Flutter Gradle tooling, with unchanged pinned Flutter source.

Sources: [JetBrains releases](https://kotlinlang.org/docs/releases.html), [advisory](https://github.com/advisories/GHSA-r937-wjx7-w2jp). The checked-in wrapper/init policy, locks/checksums, actual compiler graph and tests are implementation evidence. No claim of whole-toolchain cleanliness follows from the runtime/Pub OSV scan; build-only findings and the Gradle embedded Kotlin DSL compatibility warning remain explicit inputs to independent review.

Cost: compiler patch compatibility must be verified and maintained in the pinned build matrix. This changes the build dependency target, not product permissions or the public API. Domain cache remains a separate Task2 deliverable; Task1 domain writes fail closed.
