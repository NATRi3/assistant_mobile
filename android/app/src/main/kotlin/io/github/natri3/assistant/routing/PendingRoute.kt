package io.github.natri3.assistant.routing
// No external route or intent payload is consumed by the pairing foundation.
sealed interface PendingRoute { data object Device:PendingRoute }
