package io.github.natri3.assistant.platform
import org.junit.Test
import org.junit.Assert.*
class NativePreferenceFenceTest {
    private fun prefs(policy:Int)=mapOf("version" to 1,"delivery_route" to "telegram","widget_summary_enabled" to false,"quiet_hours" to mapOf("enabled" to false,"start" to null,"end" to null,"timezone" to "UTC","owner_policy_version" to policy))
    @Test fun sameVirtualPreferenceDifferentOwnerPolicyIsAcceptedButNotOptIn(){
        val f=NativePreferenceFence()
        f.accept("owned",1,7,prefs(1))
        f.accept("owned",1,8,prefs(2))
        assertFalse(f.current!!.widgetSummaryEnabled)
        assertEquals(8,f.current!!.foregroundEpoch)
        assertTrue(runCatching{f.accept("owned",1,8,prefs(2)+("widget_summary_enabled" to true))}.isFailure)
    }
}
