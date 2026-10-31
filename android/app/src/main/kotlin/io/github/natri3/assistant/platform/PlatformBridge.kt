package io.github.natri3.assistant.platform
import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.natri3.assistant.BuildConfig
import io.github.natri3.assistant.security.*
import java.time.Instant
class PlatformBridge(
 private val context:Context,private val channel:MethodChannel,
 private val requestUnlock:(()->Unit,()->Unit)->Unit,private val showCover:()->Unit,private val hideCover:()->Unit
):MethodChannel.MethodCallHandler {
 private val clock=NativeClock(context)
 val gate=ForegroundGate{clock.elapsed()}
 private val keys=DeviceKeys(context)
 private val vault=SessionVault(context,keys)
 private val prefs=context.getSharedPreferences("public-device-state",Context.MODE_PRIVATE)
 private var session:Map<String,Any?>?=null
 private var closingAccess:String?=null
 private val handler=android.os.Handler(android.os.Looper.getMainLooper())
 private val expire=Runnable{lock()}
 private var pendingUnlock:MethodChannel.Result?=null
 init { if(prefs.getBoolean("pending_logout",false)) destroy();channel.setMethodCallHandler(this) }
 fun resume(){gate.resume()}
 fun pause(){showCover();session=null;closingAccess=null;gate.pause();emitLock()}
 fun lock(){handler.removeCallbacks(expire);showCover();session=null;closingAccess=null;gate.lock();emitLock()}
 private fun emitLock(){channel.invokeMethod("locked",mapOf("native_epoch" to gate.epoch))}
 private fun map(args:Any?,fields:Set<String>):Map<String,Any?> {
 require(args is Map<*,*> && args.keys==fields)
 return args.entries.associate {require(it.key is String);it.key as String to it.value}
 }
 private fun noArgs(args:Any?){require(args==null)}
 private fun slot(value:Any?):String {require(value=="session"||value=="domain");return value as String}
 @Suppress("UNCHECKED_CAST")
 override fun onMethodCall(call:MethodCall,result:MethodChannel.Result) {
 try {
 when(call.method){
 "bootstrap"->{noArgs(call.arguments);result.success(mapOf("native_epoch" to gate.epoch,"api_origin" to BuildConfig.ASSISTANT_API_ORIGIN,"logout_unconfirmed" to prefs.getBoolean("logout_unconfirmed",false),"device_id" to prefs.getString("device_id",null)))}
 "unlockAndReadSession"->{
 noArgs(call.arguments);check(gate.foreground&&gate.state!=ForegroundGate.State.CLOSING&&pendingUnlock==null)
 if(gate.state==ForegroundGate.State.DESTROYED){gate.lock();emitLock()}
 check(keys.secure()){"SCREEN_LOCK_REQUIRED"};keys.ensure();pendingUnlock=result
 requestUnlock({finishUnlock()},{failUnlock()});return
 }
 "createDeviceKey"->{noArgs(call.arguments);gate.requireOpen();check(!prefs.getBoolean("pending_logout",false));keys.testAuthorization();result.success(mapOf("jwk" to keys.publicJwk().toJSONObject(),"fingerprint" to keys.fingerprint()))}
 "signDpop"->{
 val args=map(call.arguments,setOf("operation_id","resource_id","access_token"));val operation=args["operation_id"] as String
 gate.requireSign(operation);check(!context.getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
 val (route,uri)=OperationRoutes.resolve(operation,args["resource_id"] as String?,BuildConfig.ASSISTANT_API_ORIGIN)
 val access=args["access_token"] as String?
 if(route.authenticated){val owned=if(gate.state==ForegroundGate.State.CLOSING)closingAccess else session?.get("access_token");check(access!=null&&access==owned){"FOREIGN_TOKEN"}}else require(access==null)
 result.success(DpopSigner(keys.privateKey(),keys.publicJwk()).sign(route.method,uri,access,Instant.now().epochSecond))
 }
 "readPrivateCache"->{
 val args=map(call.arguments,setOf("slot"));gate.requireOpen();val s=slot(args["slot"])
 val record=if(s=="domain")PrivateCache(vault,clock).read() else vault.read(s)?.also{checkRefreshAge(it)}
 result.success(record?.filterKeys{it=="value"||it=="revision"||it=="synced_at"})
 }
 "writePrivateCache"->{
 val args=map(call.arguments,setOf("slot","value","native_epoch","expected_revision"));gate.requireOpen(args["native_epoch"] as Int)
 val s=slot(args["slot"]);val value=args["value"] as Map<String,Any?>;val expected=args["expected_revision"] as Int
 val old=vault.read(s);check(expected==((old?.get("revision") as? Number)?.toInt()?:0))
 if(s=="domain"){PrivateCache(vault,clock).write(value,expected);return}
 require(value.keys==setOf("session","pending_refresh"));val dto=validateSession(value["session"] as Map<String,Any?>)
 val prior=(old?.get("value") as? Map<*,*>)?.get("session") as? Map<*,*>
 if(prior!=null){require(dto["device_id"]==prior["device_id"]&&dto["device_version"]==prior["device_version"])}
 val pending=value["pending_refresh"]
 if(pending!=null){val p=map(pending,setOf("action_key","refresh_token","started_at"));require(OperationRoutes.validUuid(p["action_key"] as String));require(p["refresh_token"]==dto["refresh_token"]);Instant.parse(p["started_at"] as String)}
 val record=mapOf("value" to value,"revision" to expected+1,"synced_at" to Instant.now().toString(),"key_fingerprint" to keys.fingerprint(),"refresh_started_elapsed_ms" to (if(pending!=null) (old?.get("refresh_started_elapsed_ms")?:clock.elapsed()) else null),"refresh_boot" to (if(pending!=null) (old?.get("refresh_boot")?:clock.boot()) else null))
 vault.write(s,record);session=dto
 check(prefs.edit().putString("device_id",dto["device_id"] as String).commit());result.success(null)
 }
 "clearLocalState"->{val args=map(call.arguments,setOf("phase"));when(args["phase"]){
 "cover"->{showCover();check(prefs.edit().putBoolean("pending_logout",true).putBoolean("logout_unconfirmed",true).commit());closingAccess=session?.get("access_token") as? String;session=null;gate.cover()}
 "destroy"->destroy()
 else->error("INVALID_PHASE")};result.success(null)}
 "acknowledgeCover"->{val args=map(call.arguments,setOf("native_epoch"));check(gate.foreground&&gate.state!=ForegroundGate.State.OPEN&&(args["native_epoch"] as Int)==gate.epoch);hideCover();result.success(null)}
 "recordRevokeResult"->{val args=map(call.arguments,setOf("confirmed"));require(args["confirmed"] is Boolean);check(gate.state==ForegroundGate.State.DESTROYED);check(prefs.edit().putBoolean("logout_unconfirmed",!(args["confirmed"] as Boolean)).commit());result.success(null)}
 else->result.notImplemented()
 }
 }catch(_:Exception){
 // Never serialize exception messages, credentials, request bodies or paths.
 if(call.method=="unlockAndReadSession")pendingUnlock=null
 if(call.method=="unlockAndReadSession"||call.method=="signDpop"||call.method=="readPrivateCache"||call.method=="writePrivateCache")lock()
 result.error("SECURITY_BOUNDARY","Операция недоступна. Разблокируйте телефон или подключите его заново.",null)
 }
 }
 private fun finishUnlock(){
 val result=pendingUnlock?:return;pendingUnlock=null
 try {
 check(gate.foreground&&gate.state!=ForegroundGate.State.CLOSING&&gate.state!=ForegroundGate.State.DESTROYED&&!context.getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
 keys.testAuthorization();val record=vault.read("session")
 if(record!=null){check(record["key_fingerprint"]==keys.fingerprint());checkRefreshAge(record)}
 @Suppress("UNCHECKED_CAST") val dto=(record?.get("value") as? Map<String,Any?>)?.get("session") as? Map<String,Any?>
 session=dto?.let{validateSession(it)};val epoch=gate.authenticate();handler.removeCallbacks(expire);handler.postDelayed(expire,300000);hideCover();result.success(mapOf("native_epoch" to epoch,"session" to session))
 }catch(_:Exception){lock();result.error("AUTH_UNAVAILABLE","Не удалось открыть защищённую сессию. Повторное подключение может потребоваться.",null)}
 }
 private fun failUnlock(){val result=pendingUnlock;pendingUnlock=null;lock();result?.error("AUTH_CANCELLED","Разблокировка отменена",null)}
 fun cancelUnlock(){failUnlock()}
 private fun checkRefreshAge(record:Map<String,Any?>){
 val value=record["value"] as? Map<*,*> ?: error("INVALID_VAULT")
 if(value["pending_refresh"]!=null){
 val boot=(record["refresh_boot"] as? Number)?.toInt()?:error("REPAIR_REQUIRED")
 val started=(record["refresh_started_elapsed_ms"] as? Number)?.toLong()?:error("REPAIR_REQUIRED")
 check(boot>=0&&boot==clock.boot()&&clock.elapsed()-started in 0 until 60000){"REPAIR_REQUIRED"}
 }
 }
 private fun validateSession(j:Map<String,Any?>):Map<String,Any?> {
 require(j.keys==setOf("device_id","device_version","token_type","access_token","expires_in","refresh_token","refresh_expires_at","server_time"))
 require(OperationRoutes.validUuid(j["device_id"] as String));require(j["device_version"] is Int || j["device_version"] is Long);val v=(j["device_version"] as Number).toLong();require(v in 1..9007199254740991L)
 require(j["token_type"]=="DPoP"&&j["expires_in"]==600)
 for(k in listOf("access_token","refresh_token"))require(Regex("^[A-Za-z0-9_-]{43}$").matches(j[k] as String))
 Instant.parse(j["server_time"] as String);Instant.parse(j["refresh_expires_at"] as String);return j.toMap()
 }
 private fun destroy(){
 handler.removeCallbacks(expire);pendingUnlock?.error("AUTH_CANCELLED","Разблокировка отменена",null);pendingUnlock=null;showCover();session=null;closingAccess=null;gate.destroy()
 emitLock()
 vault.destroy();keys.destroy();context.getSystemService(android.app.NotificationManager::class.java).cancelAll()
 check(prefs.edit().putBoolean("pending_logout",false).commit())
 }
}
