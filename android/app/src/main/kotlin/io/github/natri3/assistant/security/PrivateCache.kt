package io.github.natri3.assistant.security
import io.github.natri3.assistant.platform.NativeClock
class PrivateCache(private val vault:SessionVault,private val clock:NativeClock) {
 fun read():Map<String,Any?>? {
 val record=vault.read("domain")?:return null
 val boot=(record["boot"] as? Number)?.toInt()?:return null;val synced=(record["sync_elapsed_ms"] as? Number)?.toLong()?:return null
 if(!VaultPolicy.usable(boot>=0&&boot==clock.boot(),synced,clock.elapsed(),true))return null
 return record
 }
 fun write(value:Map<String,Any?>,revision:Int){
 val encoded=org.json.JSONObject(value).toString().toByteArray().size
 val tasks=(value["tasks"] as? List<*>)?.size?:0;val turns=(value["chat_messages"] as? List<*>)?.size?:0
 require(VaultPolicy.capacity(encoded,tasks,turns))
 // Task2 owns the domain schema and successful-sync merge policy. Until then no
 // domain content is admitted by the public bridge, preventing invented sync age.
 error("DOMAIN_WRITER_NOT_CONFIGURED")
 }
}
