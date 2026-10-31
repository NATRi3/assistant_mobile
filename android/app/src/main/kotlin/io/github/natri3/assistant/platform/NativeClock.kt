package io.github.natri3.assistant.platform
import android.os.SystemClock
import android.content.Context
import android.provider.Settings
class NativeClock(private val context:Context) {
 fun elapsed():Long=SystemClock.elapsedRealtime()
 fun boot():Int=Settings.Global.getInt(context.contentResolver,Settings.Global.BOOT_COUNT,-1)
}
