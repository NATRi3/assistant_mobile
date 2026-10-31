package io.github.natri3.assistant.security

import io.github.natri3.assistant.platform.ClockSample

object DomainPolicy {
    fun aad(fingerprint:String,origin:String,device:String,version:Long)=DomainJson.bytes(listOf("io.github.natri3.assistant","domain",1,fingerprint,origin,device,version))
    fun usable(stamp:Map<String,Any?>,now:ClockSample):Boolean {
        val elapsed=(stamp["sync_elapsed_ms"] as Number).toLong()
        val bounds=stamp["local_clock_bounds"] as List<*>
        return (stamp["clock_generation"] as? Number)?.toLong()==now.clockGeneration&&now.boot>=0&&(stamp["boot_count"] as Number).toInt()==now.boot&&now.elapsed-elapsed in 0 until 86400000&&now.lower<=(bounds[1] as Number).toLong()&&(bounds[0] as Number).toLong()<=now.upper
    }
}
