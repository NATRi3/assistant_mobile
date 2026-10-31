package io.github.natri3.assistant.security

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import java.io.File

@RunWith(AndroidJUnit4::class)
class DomainCacheSecurityTest {
 @Test fun realAuthenticatedAtomicDomainRoundtripWrongAadAndSessionIsolation(){
  // Dedicated synthetic installation only, after a genuine native prompt.
  // Assembly/JVM success does not mean this operator-driven test has run.
  val instrumentation=InstrumentationRegistry.getInstrumentation()
  val c=instrumentation.targetContext
  val keys=DeviceKeys(c)
  assumeTrue("Configure screen lock on a dedicated synthetic installation",keys.secure())
  assumeTrue("Explicit genuine native unlock required",InstrumentationRegistry.getArguments().getString("native_unlock_completed")=="true")
  assumeTrue("Never overwrite an existing owner vault",!File(c.noBackupFilesDir,"session.v1.vault").exists()&&!File(c.noBackupFilesDir,"domain.v1.vault").exists())
  keys.ensure();keys.testAuthorization()
  val vault=SessionVault(c,keys)
  val origin="https://synthetic.invalid";val device="11111111-1111-4111-8111-111111111111"
  val session=mapOf("synthetic_session_marker" to true)
  val envelope=mapOf("synthetic_domain_marker" to true,"revision" to 1)
  try {
   vault.write("session",session)
   val cache=PrivateCache(vault,{origin},{device},{1})
   cache.write(envelope)
   assertEquals(envelope,cache.read());assertEquals(session,vault.read("session"))
   assertTrue(runCatching{vault.readDomain("https://foreign.invalid",device,1)}.isFailure)
   assertTrue(runCatching{vault.readDomain(origin,"22222222-2222-4222-8222-222222222222",1)}.isFailure)
   assertTrue(runCatching{vault.readDomain(origin,device,2)}.isFailure)
   assertFalse(File(c.noBackupFilesDir,"domain.v1.vault").readBytes().toString(Charsets.UTF_8).contains("synthetic_domain_marker"))
  }finally{vault.destroy()}
  assertFalse(File(c.noBackupFilesDir,"domain.v1.vault").exists())
 }
}
