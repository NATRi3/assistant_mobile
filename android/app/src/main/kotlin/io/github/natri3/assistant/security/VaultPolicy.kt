package io.github.natri3.assistant.security
object VaultPolicy {
 fun usable(sameBoot:Boolean,syncedMs:Long,nowMs:Long,unlocked:Boolean):Boolean=unlocked&&sameBoot&&syncedMs>=0&&nowMs>=syncedMs&&nowMs-syncedMs<86400000
 fun capacity(bytes:Int,tasks:Int,turns:Int):Boolean=bytes in 0..2097152&&tasks in 0..200&&turns in 0..20
}
