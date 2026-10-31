package io.github.natri3.assistant.security
import android.content.Context
import android.util.AtomicFile
import java.io.File
import org.json.JSONObject
import org.json.JSONArray
class SessionVault(context:Context,private val keys:DeviceKeys) {
 private val root=context.noBackupFilesDir
 private fun file(slot:String):AtomicFile {require(slot=="session"||slot=="domain");return AtomicFile(File(root,"$slot.v1.vault"))}
 private fun aad(slot:String)="io.github.natri3.assistant|v1|$slot|${keys.fingerprint()}".toByteArray(Charsets.UTF_8)
 @Synchronized fun read(slot:String):Map<String,Any?>? {
 val f=file(slot);if(!f.baseFile.exists())return null
 require(f.baseFile.length()<=2097180)
 val bytes=Aead.decrypt(keys.aes(),f.readFully(),aad(slot))
 try {return jsonMap(JSONObject(String(bytes,Charsets.UTF_8)))}finally{bytes.fill(0)}
 }
 @Synchronized fun write(slot:String,value:Map<String,Any?>){
 val bytes=JSONObject(value).toString().toByteArray(Charsets.UTF_8);require(bytes.size<=if(slot=="session")16384 else 2097152)
 val encrypted=try{Aead.encrypt(keys.aes(),bytes,aad(slot))}finally{bytes.fill(0)}
 val f=file(slot);val stream=f.startWrite();try{stream.write(encrypted);f.finishWrite(stream)}catch(e:Exception){f.failWrite(stream);throw e}
 }
 @Synchronized fun destroy(){file("session").delete();file("domain").delete()}
 companion object {
 fun jsonMap(j:JSONObject):Map<String,Any?> = j.keys().asSequence().associateWith{convert(j.get(it))}
 private fun convert(v:Any?):Any?=when(v){JSONObject.NULL->null;is JSONObject->jsonMap(v);is JSONArray->(0 until v.length()).map{convert(v.get(it))};else->v}
 }
}
