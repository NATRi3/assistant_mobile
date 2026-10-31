package io.github.natri3.assistant.security
import org.junit.Test
import org.junit.Assert.*
import javax.crypto.KeyGenerator
import io.github.natri3.assistant.platform.ClockSample
class DomainPolicyTest {
    @Test fun exactAgeBootRollbackAndClockBounds(){
        val stamp=mapOf("sync_elapsed_ms" to 100L,"boot_count" to 4,"local_clock_bounds" to listOf(10L,14L),"clock_generation" to 0L)
        assertTrue(DomainPolicy.usable(stamp,ClockSample(86400099L,4,10,14)))
        for(now in listOf(ClockSample(86400100L,4,10,14),ClockSample(99,4,10,14),ClockSample(101,-1,10,14),ClockSample(101,5,10,14),ClockSample(101,4,20,24)))assertFalse(DomainPolicy.usable(stamp,now))
    }
    @Test fun realAeadRoundtripBindsOriginDeviceVersionAndKeyFingerprint(){
        val key=KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
        val plain=DomainJson.bytes(mapOf("synthetic" to "encrypted domain"))
        val aad=DomainPolicy.aad("key","https://synthetic.invalid","device",1)
        val encrypted=Aead.encrypt(key,plain,aad)
        assertArrayEquals(plain,Aead.decrypt(key,encrypted,aad))
        for(other in listOf(DomainPolicy.aad("foreign","https://synthetic.invalid","device",1),DomainPolicy.aad("key","https://foreign.invalid","device",1),DomainPolicy.aad("key","https://synthetic.invalid","foreign",1),DomainPolicy.aad("key","https://synthetic.invalid","device",2)))assertTrue(runCatching{Aead.decrypt(key,encrypted,other)}.isFailure)
    }
    @Test fun returningWallOffsetAfterKnownClockEventDoesNotRestoreOldProjection(){
        val stamp=mapOf("sync_elapsed_ms" to 100L,"boot_count" to 4,"local_clock_bounds" to listOf(10L,14L),"clock_generation" to 0L)
        assertFalse(DomainPolicy.usable(stamp,ClockSample(101,4,10,14,1)))
    }

}
