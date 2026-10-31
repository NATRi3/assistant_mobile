package io.github.natri3.assistant.platform
import android.os.SystemClock
import android.content.Context
import android.provider.Settings
class NativeClock(private val context:Context):DomainClock {
 private val state=context.getSharedPreferences("public-device-state",Context.MODE_PRIVATE)
 fun invalidate(){val next=state.getLong("domain_clock_generation",0)+1;check(next>0&&state.edit().putLong("domain_clock_generation",next).commit())}

 override fun sample():ClockSample {val before=System.currentTimeMillis();val elapsed=elapsed();val after=System.currentTimeMillis();return ClockSample(elapsed,boot(),before-elapsed-2,after-elapsed+2,state.getLong("domain_clock_generation",0))}
 fun elapsed():Long=SystemClock.elapsedRealtime()
 fun boot():Int=Settings.Global.getInt(context.contentResolver,Settings.Global.BOOT_COUNT,-1)
}
