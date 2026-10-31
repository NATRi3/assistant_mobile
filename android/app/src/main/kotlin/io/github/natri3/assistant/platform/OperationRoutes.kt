package io.github.natri3.assistant.platform
import java.net.URI
object OperationRoutes {
 data class Route(val method:String,val path:String,val authenticated:Boolean)
 private val uuid=Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
 fun validUuid(value:String)=uuid.matches(value)
 val all=mapOf(
 "createPairing" to Route("POST","/mobile/v1/pairings",false),
 "getPairing" to Route("GET","/mobile/v1/pairings/{pairing_id}",false),
 "completePairing" to Route("POST","/mobile/v1/pairings/{pairing_id}/complete",false),
 "refreshSession" to Route("POST","/mobile/v1/sessions/refresh",false),
 "getSelfDevice" to Route("GET","/mobile/v1/devices/self",true),
 "revokeSelfDevice" to Route("DELETE","/mobile/v1/devices/self",true),
 "getDashboard" to Route("GET","/mobile/v1/dashboard",true),
 "getTask" to Route("GET","/mobile/v1/tasks/{task_id}",true),
 "completeTask" to Route("POST","/mobile/v1/tasks/{task_id}/complete",true),
 "getReminder" to Route("GET","/mobile/v1/reminders/{reminder_id}",true),
 "snoozeReminder" to Route("POST","/mobile/v1/reminders/{reminder_id}/snooze",true),
 "getMutation" to Route("GET","/mobile/v1/mutations/{action_key}",true),
 "submitChat" to Route("POST","/mobile/v1/chat/messages",true),
 "listChat" to Route("GET","/mobile/v1/chat/messages",true),
 "getChat" to Route("GET","/mobile/v1/chat/messages/{message_id}",true),
 "cancelChat" to Route("POST","/mobile/v1/chat/messages/{message_id}/cancel",true),
 "getPreferences" to Route("GET","/mobile/v1/preferences",true),
 "updatePreferences" to Route("PATCH","/mobile/v1/preferences",true),
 "updatePushRegistration" to Route("PUT","/mobile/v1/devices/self/push-registration",true),
 "deletePushRegistration" to Route("DELETE","/mobile/v1/devices/self/push-registration",true),
 "getNotification" to Route("GET","/mobile/v1/notifications/{notification_id}",true),
 "recordNotificationReceipt" to Route("POST","/mobile/v1/notification-receipts",true),
 "getChatByClientId" to Route("GET","/mobile/v1/chat/messages/by-client-id/{client_message_id}",true))
 fun resolve(operation:String,id:String?,origin:String):Pair<Route,String> {
 val u=URI(origin);require(u.scheme=="https"&&!u.host.isNullOrEmpty()&&u.userInfo==null&&u.rawPath.isNullOrEmpty()&&u.query==null&&u.fragment==null)
 val route=all[operation]?:error("OPERATION_DENIED")
 val path=if(route.path.contains('{')){require(id!=null&&validUuid(id));route.path.replace(Regex("\\{[^}]+\\}"),id)}else{require(id==null);route.path}
 return route to (origin+path)
 }
}
