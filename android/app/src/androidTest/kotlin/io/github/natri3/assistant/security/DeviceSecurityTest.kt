package io.github.natri3.assistant.security

import android.content.pm.ApplicationInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.security.KeyStore
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DeviceSecurityTest {
    @Test fun manifestDisablesBackup() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals(0, context.applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP)
    }

    @Test fun realAuthRequiredKeysAndDedicatedRevokeBeforeDestruction() {
        nativeScenario { harness ->
            harness.openFreshActivity()
            harness.unlock()
            val keys = harness.keys
            keys.testAuthorization()
            assertNull(keys.privateKey().encoded)
            assertNull(keys.aes().encoded)
            assertTrue("COVER_FAILED", harness.call("clearLocalState", mapOf("phase" to "cover")).errorCode == null)
            harness.requireRevokeWhileCovered()
            val proof = DpopSigner(keys.privateKey(), keys.publicJwk()).sign("DELETE", "https://mobile.example.invalid/mobile/v1/devices/self", null, java.time.Instant.now().epochSecond)
            assertEquals(3, proof.split('.').size)
            assertTrue("DESTROY_FAILED", harness.call("clearLocalState", mapOf("phase" to "destroy")).errorCode == null)
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            assertFalse(store.containsAlias(DeviceKeys.EC))
            assertFalse(store.containsAlias(DeviceKeys.AES))
        }
    }
}
