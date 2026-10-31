package io.github.natri3.assistant.security

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DomainCacheSecurityTest {
    @Test fun realAuthenticatedAtomicDomainRoundtripWrongAadAndSessionIsolation() {
        nativeScenario { harness ->
            harness.openFreshActivity()
            harness.unlock()
            val vault = harness.vault
            val origin = "https://synthetic.invalid"
            val device = "11111111-1111-4111-8111-111111111111"
            val session = mapOf("synthetic_session_marker" to true)
            val envelope = mapOf("synthetic_domain_marker" to true, "revision" to 1)
            vault.write("session", session)
            val cache = PrivateCache(vault, { origin }, { device }, { 1 })
            cache.write(envelope)
            assertTrue("DOMAIN_ROUNDTRIP_FAILED", envelope == cache.read())
            assertTrue("SESSION_ISOLATION_FAILED", session == vault.read("session"))
            assertTrue("FOREIGN_ORIGIN_ACCEPTED", runCatching { vault.readDomain("https://foreign.invalid", device, 1) }.isFailure)
            assertTrue("FOREIGN_DEVICE_ACCEPTED", runCatching { vault.readDomain(origin, "22222222-2222-4222-8222-222222222222", 1) }.isFailure)
            assertTrue("FOREIGN_VERSION_ACCEPTED", runCatching { vault.readDomain(origin, device, 2) }.isFailure)
            assertFalse("PLAINTEXT_DOMAIN_MARKER", File(harness.context.noBackupFilesDir, "domain.v1.vault").readText().contains("synthetic_domain_marker"))
            vault.destroy()
            assertTrue("VAULT_DELETE_FAILED", harness.vaultFiles().none { it.exists() })
        }
    }
}
