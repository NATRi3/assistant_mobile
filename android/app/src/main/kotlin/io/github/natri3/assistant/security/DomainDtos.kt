package io.github.natri3.assistant.security

import io.github.natri3.assistant.platform.OperationRoutes
import java.time.Instant
import java.time.LocalDate

object DomainDtos {
    const val MAX=9007199254740991L
    fun map(v:Any?):Map<String,Any?> {require(v is Map<*,*> && v.keys.all{it is String})
        return v.entries.associate{it.key as String to it.value}}
    fun exact(j:Map<String,Any?>,vararg fields:String){require(j.keys==fields.toSet())}
    fun number(v:Any?,min:Long=1):Long {require(v is Int || v is Long)
        return (v as Number).toLong().also{require(it in min..MAX)}}
    fun uuid(v:Any?):String {require(v is String&&OperationRoutes.validUuid(v))
        return v}
    fun text(v:Any?,max:Int,min:Int=0):String {require(v is String&&!v.contains('\u0000')&&v.codePointCount(0,v.length) in min..max)
        return v}
    fun bool(v:Any?):Boolean {require(v is Boolean)
        return v}
    fun time(v:Any?):String {require(v is String&&Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,9})?Z$").matches(v))
        Instant.parse(v)
        return v}
    fun one(v:Any?,vararg options:String):String {require(v in options)
        return v as String}
    fun task(v:Any?):Map<String,Any?> {val j=map(v)
        exact(j,"id","title","status","version","due_date","due_at","source_warning","updated_at","permitted_actions")
        uuid(j["id"])
        text(j["title"],4096)
        one(j["status"],"open","done","cancelled")
        number(j["version"])
        if(j["due_date"]!=null){val d=text(j["due_date"],10,10)
            require(Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(d))
            require(LocalDate.parse(d).toString()==d)}
        if(j["due_at"]!=null)time(j["due_at"])
        require(j["due_date"]==null||j["due_at"]==null)
        bool(j["source_warning"])
        time(j["updated_at"])
        actions(j["permitted_actions"],"complete")
        return j}
    fun actions(v:Any?,name:String){require(v is List<*>&&v.size<=1&&v.all{it==name})}
    fun summary(v:Any?):Map<String,Any?> {val j=map(v)
        exact(j,"id","due_at","version","source_warning")
        uuid(j["id"])
        time(j["due_at"])
        number(j["version"])
        bool(j["source_warning"])
        return j}
    fun reminder(v:Any?):Map<String,Any?> {val j=map(v)
        exact(j,"id","text","status","active","version","due_at","timezone","linked_task_id","source_warning","updated_at","permitted_actions")
        uuid(j["id"])
        text(j["text"],4096)
        one(j["status"],"scheduled","cancelled","expired")
        bool(j["active"])
        number(j["version"])
        time(j["due_at"])
        text(j["timezone"],100,1)
        if(j["linked_task_id"]!=null)uuid(j["linked_task_id"])
        bool(j["source_warning"])
        time(j["updated_at"])
        actions(j["permitted_actions"],"snooze_10m")
        return j}
    fun preferences(v:Any?):Map<String,Any?> {val j=map(v)
        exact(j,"version","delivery_route","widget_summary_enabled","quiet_hours")
        number(j["version"])
        one(j["delivery_route"],"telegram","mobile","both")
        bool(j["widget_summary_enabled"])
        val q=map(j["quiet_hours"])
        exact(q,"enabled","start","end","timezone","owner_policy_version")
        number(q["owner_policy_version"])
        text(q["timezone"],100,1)
        if(bool(q["enabled"])){for(k in listOf("start","end"))require(q[k] is String&&Regex("^([01][0-9]|2[0-3]):[0-5][0-9]$").matches(q[k] as String))
            require(q["start"]!=q["end"])}else require(q["start"]==null&&q["end"]==null)
        return j}
    fun dashboard(v:Any?):Map<String,Any?> {val j=map(v)
        exact(j,"server_time","snapshot_id","context_epoch","tasks","total_open_count","nearest_reminder","preferences","next_cursor")
        time(j["server_time"])
        uuid(j["snapshot_id"])
        number(j["context_epoch"])
        number(j["total_open_count"],0)
        preferences(j["preferences"])
        val tasks=j["tasks"]
        require(tasks is List<*>&&tasks.size<=50&&DomainJson.bytes(tasks).size<=196608)
        val ids=tasks.map{task(it)["id"]}
        require(ids.toSet().size==ids.size)
        if(j["nearest_reminder"]!=null)summary(j["nearest_reminder"])
        if(j["next_cursor"]!=null)text(j["next_cursor"],1024,1)
        return j}
    fun device(v:Any?):Map<String,Any?> {val j=map(v)
        exact(j,"device_id","device_label","device_version","state","fingerprint","created_at","registration_version","context_epoch")
        uuid(j["device_id"])
        text(j["device_label"],60)
        number(j["device_version"])
        require(j["state"]=="active")
        text(j["fingerprint"],43)
        time(j["created_at"])
        number(j["registration_version"],0)
        number(j["context_epoch"])
        return j}
    fun receipt(v:Any?):Map<String,Any?> {val j=map(v)
        val fields=setOf("effect_id","resource_id","resource_kind","version","changed_at","replayed")
        require(j.keys.containsAll(fields)&&j.keys.all{it in fields||it=="related_task_version"||it=="related_reminder_version"})
        uuid(j["effect_id"])
        uuid(j["resource_id"])
        one(j["resource_kind"],"task","reminder","chat","preferences","push_registration")
        number(j["version"])
        time(j["changed_at"])
        bool(j["replayed"])
        for(k in listOf("related_task_version","related_reminder_version"))if(j.containsKey(k))number(j[k])
        return j}
}
