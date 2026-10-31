package io.github.natri3.assistant.security
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import android.content.pm.ApplicationInfo
import java.security.KeyStore
import io.github.natri3.assistant.platform.ForegroundGate
@RunWith(AndroidJUnit4::class)
class DeviceSecurityTest {
 @Test fun manifestDisablesBackup(){val c=InstrumentationRegistry.getInstrumentation().targetContext;assertEquals(0,c.applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP)}
 @Test fun realAuthRequiredKeysAndDedicatedRevokeBeforeDestruction(){
 // Explicit operator-driven test: configure screen lock and unlock using the
 // native app prompt immediately before this run. Never substitutes host keys.
 val c=InstrumentationRegistry.getInstrumentation().targetContext;val keys=DeviceKeys(c)
 assumeTrue("Device needs an operator-configured screen lock",keys.secure())
 assumeTrue("Run after genuine native unlock; this is not unattended runtime evidence",InstrumentationRegistry.getArguments().getString("native_unlock_completed")=="true")
 keys.ensure();keys.testAuthorization();assertNull(keys.privateKey().encoded);assertNull(keys.aes().encoded)
 val gate=ForegroundGate{android.os.SystemClock.elapsedRealtime()};gate.resume();gate.authenticate();gate.cover();gate.requireSign("revokeSelfDevice")
 val proof=DpopSigner(keys.privateKey(),keys.publicJwk()).sign("DELETE","https://mobile.example.invalid/mobile/v1/devices/self",null,java.time.Instant.now().epochSecond);assertEquals(3,proof.split('.').size)
 keys.destroy();gate.destroy();val store=KeyStore.getInstance("AndroidKeyStore").apply{load(null)};assertFalse(store.containsAlias(DeviceKeys.EC));assertFalse(store.containsAlias(DeviceKeys.AES))
 }
}
