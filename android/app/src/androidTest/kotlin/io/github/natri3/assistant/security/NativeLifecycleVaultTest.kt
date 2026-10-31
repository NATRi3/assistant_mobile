package io.github.natri3.assistant.security

import android.os.SystemClock
import android.security.keystore.KeyInfo
import android.security.keystore.UserNotAuthenticatedException
import android.util.AtomicFile
import android.view.KeyEvent
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.security.KeyFactory
import java.security.Signature
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeLifecycleVaultTest {
    private val device = "11111111-1111-4111-8111-111111111111"
    private val origin = "https://synthetic.invalid"
    private fun session(access: String = "A".repeat(43)): Map<String, Any?> = mapOf(
        "device_id" to device, "device_version" to 1, "token_type" to "DPoP",
        "access_token" to access, "expires_in" to 600, "refresh_token" to "B".repeat(43),
        "refresh_expires_at" to "2026-11-30T00:00:00Z", "server_time" to "2026-10-31T00:00:00Z"
    )
    private fun writeArguments(epoch: Int, revision: Int, dto: Map<String, Any?> = session()) = mapOf(
        "slot" to "session", "value" to mapOf("session" to dto, "pending_refresh" to null),
        "native_epoch" to epoch, "expected_revision" to revision
    )
    private fun assertDenied(harness: NativeDeviceHarness) {
        assertTrue("PROTECTED_READ_ACCEPTED", harness.call("readPrivateCache", mapOf("slot" to "session")).errorCode == "SECURITY_BOUNDARY")
        assertTrue("PROTECTED_SIGN_ACCEPTED", harness.call("signDpop", mapOf("operation_id" to "revokeSelfDevice", "resource_id" to null, "access_token" to null)).errorCode == "SECURITY_BOUNDARY")
        harness.assertLocked()
    }
    private fun authDenial(operation: () -> Unit) {
        val failure = runCatching(operation).exceptionOrNull()
        assertTrue("AUTH_REQUIRED_OPERATION_SUCCEEDED", failure != null)
        val authFailure = generateSequence(failure) { it.cause }.take(10).any { it is UserNotAuthenticatedException }
        assertTrue("FAILURE_NOT_AUTHENTICATION_DENIAL", authFailure)
    }

    @Test fun expiredAuthenticationDeniesBothKeysUntilNativePrompt() {
        nativeScenario { harness ->
            harness.openFreshActivity()
            harness.keys.ensure()
            val fingerprint = harness.keys.fingerprint()
            val aes = harness.keys.aes()
            val ec = harness.keys.privateKey()
            val ecInfo = KeyFactory.getInstance(ec.algorithm, "AndroidKeyStore").getKeySpec(ec, KeyInfo::class.java)
            val aesInfo = SecretKeyFactory.getInstance(aes.algorithm, "AndroidKeyStore").getKeySpec(aes, KeyInfo::class.java) as KeyInfo
            NativeDeviceHarness.metric("ec_security_level", ecInfo.securityLevel.toString())
            NativeDeviceHarness.metric("aes_security_level", aesInfo.securityLevel.toString())
            // No credential entry during this monotonic wait. Production validity stays 300s.
            val start = SystemClock.elapsedRealtime()
            while (SystemClock.elapsedRealtime() - start < 305000) SystemClock.sleep(250)
            NativeDeviceHarness.metric("expiry_wait_ms", (SystemClock.elapsedRealtime() - start).toString())
            authDenial { Signature.getInstance("SHA256withECDSA").apply { initSign(ec); update(byteArrayOf(1)); sign() } }
            authDenial { Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, aes); doFinal(byteArrayOf(1)) } }
            harness.unlock()
            assertTrue("EC_KEY_REPLACED", fingerprint == harness.keys.fingerprint())
            assertTrue("AES_KEY_REPLACED", aes == harness.keys.aes())
            harness.keys.testAuthorization()
        }
    }

    @Test fun pauseAndRecreateFenceSessionAndEpoch() {
        nativeScenario { harness ->
            harness.openFreshActivity()
            harness.unlock()
            val oldEpoch = harness.epoch()
            assertTrue("INITIAL_WRITE_FAILED", harness.call("writePrivateCache", writeArguments(oldEpoch, 0)).errorCode == null)
            val committed = harness.vault.read("session")
            harness.moveTo(Lifecycle.State.CREATED)
            harness.assertLocked()
            assertDenied(harness)
            harness.moveTo(Lifecycle.State.RESUMED)
            harness.unlock()
            assertTrue("SAME_BRIDGE_EPOCH_NOT_FENCED", harness.epoch() != oldEpoch)
            val current = harness.call("readPrivateCache", mapOf("slot" to "session"))
            assertTrue("CURRENT_REVISION_UNAVAILABLE", current.errorCode == null)
            val revision = ((current.value as Map<*, *>)["revision"] as Number).toInt()
            assertEquals(1, revision)
            val stale = harness.call("writePrivateCache", writeArguments(oldEpoch, revision, session("C".repeat(43))))
            assertTrue("STALE_EPOCH_ACCEPTED", stale.errorCode == "SECURITY_BOUNDARY")
            harness.assertLocked()
            // Inspect committed ciphertext through the real vault, without reopening the gate.
            assertTrue("STALE_WRITE_CHANGED_VAULT", committed == harness.vault.read("session"))
            harness.recreate()
            harness.assertLocked()
            assertDenied(harness)
            val restored = harness.unlock()
            assertTrue("RECREATED_SESSION_NOT_RESTORED", (restored.value as Map<*, *>)["session"] == session())
            assertTrue("RECREATED_READ_FAILED", harness.call("readPrivateCache", mapOf("slot" to "session")).errorCode == null)
            // Retain a pending old Result across actual Activity/Flutter-engine destruction.
            val oldCallback = harness.beginUnlock()
            harness.awaitCredentialWindow()
            harness.recreate()
            assertTrue("DESTROYED_ACTIVITY_UNLOCK_COMPLETED", oldCallback.get(10, TimeUnit.SECONDS).errorCode == "AUTH_CANCELLED")
            harness.assertLocked()
            assertDenied(harness)
        }
    }

    @Test fun cancelNativePromptLeavesProtectedCallsLocked() {
        nativeScenario { harness ->
            harness.openFreshActivity()
            val cancelled = harness.beginUnlock()
            harness.awaitCredentialWindow()
            harness.press(KeyEvent.KEYCODE_BACK)
            assertTrue("BACK_DID_NOT_CANCEL", cancelled.get(10, TimeUnit.SECONDS).errorCode == "AUTH_CANCELLED")
            harness.awaitForeground()
            assertDenied(harness)
            val backgrounded = harness.beginUnlock()
            harness.awaitCredentialWindow()
            harness.press(KeyEvent.KEYCODE_HOME)
            assertTrue("HOME_DID_NOT_CANCEL", backgrounded.get(10, TimeUnit.SECONDS).errorCode == "AUTH_CANCELLED")
            harness.bringForward()
            SystemClock.sleep(1000)
            assertDenied(harness)
        }
    }

    @Test fun interruptedAtomicWritePreservesCommittedVaultAndDestroyRemovesSidecars() {
        nativeScenario { harness ->
            harness.openFreshActivity()
            harness.unlock()
            assertTrue("INITIAL_WRITE_FAILED", harness.call("writePrivateCache", writeArguments(harness.epoch(), 0)).errorCode == null)
            val committed = harness.vault.read("session")
            val domain = mapOf("synthetic_atomic_marker" to true)
            harness.vault.writeDomain(domain, origin, device, 1)
            val base = File(harness.context.noBackupFilesDir, "session.v1.vault")
            // Close without finishWrite/failWrite to model an interrupted replacement.
            AtomicFile(base).startWrite().use { it.write("incomplete synthetic replacement".toByteArray()) }
            assertTrue("ATOMIC_NEW_MISSING", File(base.path + ".new").exists())
            val recovered = SessionVault(harness.context, harness.keys)
            assertTrue("COMMITTED_VAULT_NOT_RECOVERED", committed == recovered.read("session"))
            assertTrue("FOREIGN_AAD_ACCEPTED", runCatching { recovered.readDomain("https://foreign.invalid", device, 1) }.isFailure)
            // Leave both sidecar types for production destruction to remove.
            for (slot in listOf("session", "domain")) {
                for (suffix in listOf(".new", ".bak")) File(harness.context.noBackupFilesDir, "$slot.v1.vault$suffix").writeBytes(byteArrayOf(0))
            }
            assertTrue("PRODUCTION_DESTROY_FAILED", harness.call("clearLocalState", mapOf("phase" to "destroy")).errorCode == null)
            assertTrue("VAULT_SIDECAR_REMAINS", harness.vaultFiles().none { it.exists() })
        }
    }
}
