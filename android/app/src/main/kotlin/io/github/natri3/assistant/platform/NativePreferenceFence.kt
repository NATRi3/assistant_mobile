package io.github.natri3.assistant.platform
import io.github.natri3.assistant.security.DomainDtos

data class PreferenceFence(val deviceId:String,val deviceVersion:Long,val prefVersion:Long,val foregroundEpoch:Int,val deliveryRoute:String,val widgetSummaryEnabled:Boolean)
class NativePreferenceFence {
    var current:PreferenceFence?=null
    private set
    fun accept(deviceId:String,deviceVersion:Long,epoch:Int,preferences:Map<String,Any?>){
        DomainDtos.preferences(preferences)
        val next=PreferenceFence(deviceId,deviceVersion,DomainDtos.number(preferences["version"]),epoch,preferences["delivery_route"] as String,preferences["widget_summary_enabled"] as Boolean)
        current?.let{old->check(old.deviceId==next.deviceId&&old.deviceVersion==next.deviceVersion)
            check(next.prefVersion>=old.prefVersion)
            if(next.prefVersion==old.prefVersion)check(next.deliveryRoute==old.deliveryRoute&&next.widgetSummaryEnabled==old.widgetSummaryEnabled)}
        current=next
    }
    fun clear(){current=null}
}
