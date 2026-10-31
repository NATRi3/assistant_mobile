package io.github.natri3.assistant.security
import org.junit.Test
import org.junit.Assert.*
class VaultPolicyTest {
 @Test fun cacheExpiresWithoutExtendingOnAuthRefresh() {
 assertFalse(VaultPolicy.usable(false,100,101,true)); assertFalse(VaultPolicy.usable(true,100,99,true)); assertFalse(VaultPolicy.usable(true,100,101,false))
 assertTrue(VaultPolicy.usable(true,100,86400099,true)); assertFalse(VaultPolicy.usable(true,100,86400100,true))
 assertTrue(VaultPolicy.capacity(2097152,200,20)); assertFalse(VaultPolicy.capacity(2097153,1,1)); assertFalse(VaultPolicy.capacity(5,201,0)); assertFalse(VaultPolicy.capacity(5,0,21))
 }
}
