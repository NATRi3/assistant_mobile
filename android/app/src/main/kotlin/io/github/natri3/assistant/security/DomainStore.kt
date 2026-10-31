package io.github.natri3.assistant.security

import io.github.natri3.assistant.platform.*
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.security.MessageDigest

interface DomainStorage {fun read():Map<String,Any?>?
    fun write(value:Map<String,Any?>)}
class DomainFailure(val code:String):RuntimeException()

// Called only on the serialized foreground bridge. No network and no caller clock.
class DomainStore(private val storage:DomainStorage,private val clock:DomainClock,private val access:DomainAccessState) {
    private val tickets=DomainReadTickets(clock)
    private val preferenceFence=NativePreferenceFence()
    private var origin=""
    private var device=""
    private var deviceVersion=0L
    private var epoch=0
    private var verified=false
    private var dashboardEstablished=false
    private var contextFloor=0L
    private var policyFloor=0L
    private val livePrepared=mutableSetOf<String>()
    private val reminderLinks=mutableMapOf<String,String?>()
    private var generation=-1
    private var sequenceSeeded=false
    fun bind(origin:String,id:String,version:Long,epoch:Int){
        require(origin.startsWith("https://"))
        DomainDtos.uuid(id)
        DomainDtos.number(version)
        if(this.origin!=origin||device!=id||deviceVersion!=version||this.epoch!=epoch){close()
            this.origin=origin
            device=id
            deviceVersion=version
            this.epoch=epoch}
    }
    fun denyAccess(){access.denied=true;close()}
    fun requireOperation(operation:String){
        if(access.denied&&operation !in setOf("createPairing","getPairing","completePairing","refreshSession","getSelfDevice","getDashboard","revokeSelfDevice"))throw DomainFailure("DOMAIN_ACCESS_DENIED")
    }
    private fun requirePermitted(){if(access.denied)throw DomainFailure("DOMAIN_ACCESS_DENIED")}
    fun close(){sequenceSeeded=false
        verified=false
        dashboardEstablished=false
        contextFloor=0
        policyFloor=0
        generation=-1
        livePrepared.clear()
        reminderLinks.clear()
        tickets.clear()
        preferenceFence.clear()}
    private fun scopeKey()=DomainJson.encode(listOf(origin,device,deviceVersion,epoch,contextFloor,policyFloor))
    private fun current():Map<String,Any?>?=storage.read()?.also{validateEnvelope(it)}
    private fun validateEnvelope(j:Map<String,Any?>){
        if(j["schema_version"]!=1)throw DomainFailure("DOMAIN_UNSUPPORTED_SCHEMA")
        DomainDtos.exact(j,"schema_version","revision","scope","dashboard","tasks_by_id","reminders_by_id","pending_actions_by_key","reserved_sections")
        DomainDtos.number(j["revision"])
        val s=DomainDtos.map(j["scope"])
        DomainDtos.exact(s,"api_origin","device_id","device_version","context_epoch","owner_policy_version")
        check(s["api_origin"]==origin&&s["device_id"]==device&&DomainDtos.number(s["device_version"])==deviceVersion)
        DomainDtos.number(s["context_epoch"])
        DomainDtos.number(s["owner_policy_version"])
        for(k in listOf("tasks_by_id","reminders_by_id","pending_actions_by_key","reserved_sections"))DomainDtos.map(j[k])
        val reserved=DomainDtos.map(j["reserved_sections"])
        reserved[DomainEntityFloors.SECTION]?.let{DomainEntityFloors.validate(it)}
        if(reserved.values.any{DomainDtos.map(it)["schema_version"]!=1})throw DomainFailure("DOMAIN_UNSUPPORTED_SCHEMA")
        check(DomainJson.bytes(j).size<=2097152)
    }
    fun begin(operation:String,resource:String?,cursor:String?,viewGeneration:Int):DomainTicket {
        if(!sequenceSeeded){
            val saved=current()
            val maximum=if(saved==null)0L else listOf("tasks_by_id","reminders_by_id").flatMap{field->DomainDtos.map(saved[field]).values}.maxOfOrNull{DomainDtos.number(DomainDtos.map(DomainDtos.map(it)["stamp"])["ticket_sequence"],0)}?:0L
            tickets.seedSequence(maximum);sequenceSeeded=true
        }
        if(operation!="getSelfDevice"&&operation!="getDashboard")requirePermitted()
        if(operation!="getSelfDevice")check(verified)
        if(operation=="getDashboard"){
            if(cursor==null){check(viewGeneration>generation)
                generation=viewGeneration
                tickets.supersedeAll()}
            else check(viewGeneration==generation)
        }
        return tickets.begin(epoch,operation,resource,cursor,viewGeneration,scopeKey())
    }
    fun cancel(id:String){tickets.cancel(id)}
    private fun revision(j:Map<String,Any?>?)=(j?.get("revision") as? Number)?.toInt()?:0
    private fun checkRevision(j:Map<String,Any?>?,expected:Int){if(revision(j)!=expected)throw DomainFailure("DOMAIN_REVISION_CONFLICT")}
    private fun scoped(context:Long,policy:Long)=mapOf("api_origin" to origin,"device_id" to device,"device_version" to deviceVersion,"context_epoch" to context,"owner_policy_version" to policy)
    private fun empty(scope:Map<String,Any?>)=mapOf<String,Any?>("schema_version" to 1,"revision" to 1,"scope" to scope,"dashboard" to null,"tasks_by_id" to emptyMap<String,Any?>(),"reminders_by_id" to emptyMap<String,Any?>(),"pending_actions_by_key" to emptyMap<String,Any?>(),"reserved_sections" to emptyMap<String,Any?>())
    private fun purge(old:Map<String,Any?>,context:Long,policy:Long):Map<String,Any?> = empty(scoped(context,policy)) + mapOf("revision" to revision(old)+1,"pending_actions_by_key" to old["pending_actions_by_key"])
    fun commit(id:String,status:Int,date:String?,body:Map<String,Any?>,expected:Int):Map<String,Any?> {
        check(status==200)
        require(date!=null)
        val observed=ZonedDateTime.parse(date,DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toString()
        val ticket=tickets.requireTicket(id,epoch,scopeKey()){known->
            // Benign cancellation never exempts malformed/foreign responses from
            // the existing boundary. Validation precedes the typed discard.
            when(known.operation){
                "getSelfDevice"->{val dto=DomainDtos.device(body);check(dto["device_id"]==device&&DomainDtos.number(dto["device_version"])==deviceVersion)}
                "getDashboard"->DomainDtos.dashboard(body)
                "getTask"->check(DomainDtos.task(body)["id"]==known.resource)
                "getReminder"->check(DomainDtos.reminder(body)["id"]==known.resource)
            }
        }
        var old=current()
        checkRevision(old,expected)
        if(ticket.operation=="getSelfDevice"){
            val dto=DomainDtos.device(body)
            check(dto["device_id"]==device&&DomainDtos.number(dto["device_version"])==deviceVersion)
            val next=DomainDtos.number(dto["context_epoch"])
            val stored=old?.let{DomainDtos.number(DomainDtos.map(it["scope"])["context_epoch"])}?:0
            check(next>=maxOf(contextFloor,stored))
            contextFloor=next
            policyFloor=maxOf(policyFloor,old?.let{DomainDtos.number(DomainDtos.map(it["scope"])["owner_policy_version"])}?:0)
            if(old!=null&&next>stored){old=purge(old,next,policyFloor)
                reminderLinks.clear()
                storage.write(old)
                dashboardEstablished=false}
            tickets.supersedeAll(ticket);tickets.consume(ticket)
            verified=true
            return ack(revision(old),true)
        }
        check(verified)
        if(ticket.operation!="getDashboard")requirePermitted()
        if(ticket.operation=="getDashboard"){
            val dto=DomainDtos.dashboard(body)
            check(ticket.generation==generation)
            val context=DomainDtos.number(dto["context_epoch"])
            val pref=DomainDtos.preferences(dto["preferences"])
            val policy=DomainDtos.number(DomainDtos.map(pref["quiet_hours"])["owner_policy_version"])
            val storedScope=old?.let{DomainDtos.map(it["scope"])}
            check(context>=maxOf(contextFloor,storedScope?.let{DomainDtos.number(it["context_epoch"])}?:0))
            check(policy>=maxOf(policyFloor,storedScope?.let{DomainDtos.number(it["owner_policy_version"])}?:0))
            old?.get("dashboard")?.let{cached->val before=DomainDtos.map(DomainDtos.map(DomainDtos.map(cached)["header"])["preferences"])
                val priorVersion=DomainDtos.number(before["version"])
                val nextVersion=DomainDtos.number(pref["version"])
                check(nextVersion>=priorVersion)
                if(nextVersion==priorVersion)check(before.filterKeys{it!="quiet_hours"}==pref.filterKeys{it!="quiet_hours"})}
            preferenceFence.accept(device,deviceVersion,epoch,pref)
            val changed=context>contextFloor||policy>policyFloor
            contextFloor=context
            policyFloor=policy
            if(old==null)old=empty(scoped(context,policy))+mapOf("revision" to 0)
            if(changed){old=purge(old,context,policy)
                storage.write(old)
                tickets.clear()
                reminderLinks.clear()}
            var floors=DomainEntityFloors.from(old)
            val entries=DomainDtos.map(old["tasks_by_id"]).toMutableMap()
            for(item in dto["tasks"] as List<*>){val task=DomainDtos.task(item)
                val id=task["id"] as String
                val v=DomainDtos.number(task["version"])
                DomainEntityFloors.check(floors,"tasks",id,v)
                merge(entries,task,ticket,observed)
                floors=DomainEntityFloors.retire(floors,"tasks",id,v)}
            dto["nearest_reminder"]?.let{raw->val reminder=DomainDtos.summary(raw)
                DomainEntityFloors.check(floors,"reminders",reminder["id"] as String,DomainDtos.number(reminder["version"]))}
            val priorDashboard=old["dashboard"]?.let{DomainDtos.map(it)}
            val ids=(if(ticket.cursor==null)emptyList<String>() else {
                check(priorDashboard!=null&&priorDashboard["view_generation"]==ticket.generation&&DomainDtos.map(priorDashboard["header"])["next_cursor"]==ticket.cursor)
                (priorDashboard["task_ids"] as List<*>).map{it as String}
            })+(dto["tasks"] as List<*>).map{DomainDtos.map(it)["id"] as String}
            val header=(if(ticket.cursor==null)dto else DomainDtos.map(priorDashboard!!["header"])).filterKeys{it!="tasks"} + mapOf("next_cursor" to dto["next_cursor"])
            val dashboard=mapOf("header" to header,"task_ids" to ids.distinct(),"view_generation" to generation,"stamp" to (if(ticket.cursor==null)stamp(ticket,observed) else priorDashboard!!["stamp"]))
            val next=DomainEntityFloors.put(old+mapOf("scope" to scoped(context,policy),"dashboard" to dashboard,"tasks_by_id" to entries,"revision" to revision(old)+1),floors)
            val cached=ticket.stamp.boot>=0&&admit(next)
            dashboardEstablished=true
            access.denied=false
            if(!changed)tickets.consume(ticket)
            return ack(if(cached)revision(next)else revision(old),cached)
        }
        check(old!=null&&DomainDtos.number(DomainDtos.map(old["scope"])["context_epoch"])==contextFloor)
        val field=if(ticket.operation=="getTask")"tasks_by_id" else "reminders_by_id"
        val dto=if(field=="tasks_by_id")DomainDtos.task(body)else DomainDtos.reminder(body)
        check(dto["id"]==ticket.resource)
        val kind=if(field=="tasks_by_id")"tasks"else"reminders"
        var floors=DomainEntityFloors.from(old)
        DomainEntityFloors.check(floors,kind,dto["id"] as String,DomainDtos.number(dto["version"]))
        val entries=DomainDtos.map(old[field]).toMutableMap()
        merge(entries,dto,ticket,observed)
        floors=DomainEntityFloors.retire(floors,kind,dto["id"] as String,DomainDtos.number(dto["version"]))
        val cachedDashboard=old["dashboard"]?.let{DomainDtos.map(it)}
        val nearest=cachedDashboard?.let{DomainDtos.map(it["header"])["nearest_reminder"]}?.let{DomainDtos.map(it)}
        val terminalTask=field=="tasks_by_id"&&dto["status"]!="open"&&((cachedDashboard?.get("task_ids") as? List<*>)?.contains(dto["id"])==true)
        val obsoleteNearest=field=="reminders_by_id"&&nearest!=null&&nearest["id"]==dto["id"]&&(dto["version"]!=nearest["version"]||dto["due_at"]!=nearest["due_at"]||dto["source_warning"]!=nearest["source_warning"]||dto["status"]!="scheduled"||dto["active"]!=true)
        val invalidateHeader=terminalTask||obsoleteNearest
        val next=DomainEntityFloors.put(old+mapOf(field to entries,"dashboard" to (if(invalidateHeader)null else old["dashboard"]),"revision" to revision(old)+1),floors)
        val cached=ticket.stamp.boot>=0&&admit(next)
        var committedRevision=if(cached)revision(next)else revision(old)
        val previous=DomainDtos.map(old[field])[dto["id"]]?.let{DomainDtos.map(it)["dto"]}
        if(!cached&&(obsoleteNearest||(previous!=null&&previous!=dto))){
            // A valid current read must not leave an older private copy eligible
            // merely because the replacement did not fit. This smaller atomic
            // invalidation preserves pending/reserved data and does not mint age.
            val hidden=old+mapOf(field to DomainDtos.map(old[field]).filterKeys{it!=dto["id"]},"dashboard" to null,"revision" to revision(old)+1)
            storage.write(hidden);committedRevision=revision(hidden)
            tickets.supersedeAll(ticket)
        }
        if(field=="reminders_by_id"){
            reminderLinks[dto["id"] as String]=dto["linked_task_id"] as String?
            // An accepted current detail is a summary-admission barrier. Any
            // outstanding Dashboard may have observed the older version,
            // derived warning or active state; later new reads remain valid.
            tickets.supersedeOperation("getDashboard")
        }
        tickets.consume(ticket)
        return ack(committedRevision,cached)
    }
    private fun ack(revision:Int,cached:Boolean)=mapOf("revision" to revision,"native_epoch" to epoch,"cached" to cached)
    private fun stamp(t:DomainTicket,observed:String)=mapOf("ticket_sequence" to t.sequence,"clock_generation" to t.stamp.clockGeneration,"sync_elapsed_ms" to t.stamp.elapsed,"boot_count" to t.stamp.boot,"local_clock_bounds" to listOf(t.stamp.lower,t.stamp.upper),"server_observed_at" to observed)
    private fun usable(stamp:Any?)=DomainPolicy.usable(DomainDtos.map(stamp),clock.sample())
    private fun stable(dto:Map<String,Any?>)=dto.filterKeys{it!="source_warning"&&it!="permitted_actions"}
    private fun merge(entries:MutableMap<String,Any?>,dto:Map<String,Any?>,t:DomainTicket,date:String){
        val id=dto["id"] as String
        val old=entries[id]?.let{DomainDtos.map(it)}
        if(old!=null){val prior=DomainDtos.map(old["dto"])
            val before=DomainDtos.number(prior["version"])
            val after=DomainDtos.number(dto["version"])
            val s=DomainDtos.map(old["stamp"])
            if((s["boot_count"] as Number).toInt()==t.stamp.boot&&(t.stamp.elapsed<(s["sync_elapsed_ms"] as Number).toLong()||t.sequence<=(s["ticket_sequence"] as Number).toLong()))throw DomainReadSuperseded()
            check(after>=before)
            if(after==before)check(stable(prior)==stable(dto))}
        entries[id]=mapOf("dto" to DomainJson.copy(dto),"stamp" to stamp(t,date))
    }
    // Evict replaceable private projections only. Recovery/reserved payloads stay intact.
    private fun admit(candidate:Map<String,Any?>,protectedActions:Set<String> = emptySet()):Boolean {
        var next=candidate
        fun fits():Boolean {val reserved=DomainDtos.map(next["reserved_sections"])
            val turns=reserved.values.sumOf{((DomainDtos.map(it)["turns"] as? List<*>)?.size?:0)}
            return DomainJson.bytes(next).size<=2097152&&DomainDtos.map(next["tasks_by_id"]).size<=200&&turns<=20}
        if(!fits()){
            val tasks=DomainDtos.map(next["tasks_by_id"]).toMutableMap()
            val reminders=DomainDtos.map(next["reminders_by_id"]).toMutableMap()
            val protected=(next["dashboard"]?.let{DomainDtos.map(it)["task_ids"]} as? List<*>)?.toSet()?:emptySet<Any?>()
            val candidates=(tasks.keys.filter{it !in protected}.map{"tasks_by_id" to it}+reminders.keys.map{"reminders_by_id" to it}).sortedBy{(DomainDtos.map(DomainDtos.map((if(it.first=="tasks_by_id")tasks else reminders)[it.second])["stamp"])["sync_elapsed_ms"] as Number).toLong()}
            for((field,id) in candidates){if(fits())break
                if(field=="tasks_by_id")tasks.remove(id)else reminders.remove(id)
                next=next+mapOf("tasks_by_id" to tasks.toMap(),"reminders_by_id" to reminders.toMap())}
        }
        if(!fits()){
            val pending=DomainDtos.map(next["pending_actions_by_key"]).toMutableMap()
            for(key in pending.keys.toList()){if(fits())break
                val p=DomainDtos.map(pending[key])
                if(key !in protectedActions&&p["state"] in setOf("confirmed","rejected")){pending.remove(key)
                    next=next+mapOf("pending_actions_by_key" to pending.toMap())}}
        }
        if(!fits())return false
        storage.write(next)
        return true
    }
    fun frame():Map<String,Any?> {
        val old=current()
        val rev=revision(old)
        fun redacted()=mapOf("policy_denied" to access.denied,"revision" to rev,"needs_sync" to true,"dashboard" to null,"tasks_by_id" to emptyMap<String,Any?>(),"reminders_by_id" to emptyMap<String,Any?>(),"pending_actions_by_key" to emptyMap<String,Any?>(),"scope" to null,"last_sync" to null,"task_synced_at_by_id" to emptyMap<String,Any?>(),"reminder_synced_at_by_id" to emptyMap<String,Any?>())
        if(access.denied||!verified||old==null)return redacted()
        val scope=DomainDtos.map(old["scope"])
        if(DomainDtos.number(scope["context_epoch"])!=contextFloor||DomainDtos.number(scope["owner_policy_version"])!=policyFloor)return redacted()
        fun visible(field:String)=DomainDtos.map(old[field]).filterValues{usable(DomainDtos.map(it)["stamp"])}.mapValues{DomainDtos.map(it.value)["dto"]}
        val unresolved=DomainDtos.map(old["pending_actions_by_key"]).values.map{DomainDtos.map(it)}.filter{it["state"] in setOf("prepared","unknown")}
        val blockedTasks=unresolved.filter{it["operation"]=="completeTask"}.map{it["resource_id"]}.toSet()
        val blockedReminders=unresolved.filter{it["operation"]=="snoozeReminder"}.map{it["resource_id"]}.toSet()
        val tasks=if(unresolved.any{it["operation"]=="snoozeReminder"})emptyMap()else visible("tasks_by_id").filterKeys{it !in blockedTasks}
        val reminders=if(unresolved.any{it["operation"]=="completeTask"})emptyMap()else visible("reminders_by_id").filterKeys{it !in blockedReminders}
        val cached=old["dashboard"]?.let{DomainDtos.map(it)}?.takeIf{unresolved.isEmpty()&&usable(it["stamp"])}
        val ids=(cached?.get("task_ids") as? List<*>)?:emptyList<Any?>()
        val dashboard=cached?.let{DomainDtos.map(it["header"])+mapOf("tasks" to ids.mapNotNull{tasks[it]})}
        val pending=if(dashboardEstablished)DomainDtos.map(old["pending_actions_by_key"]).mapValues{(k,v)->val p=DomainDtos.map(v)
            if(p["state"]=="prepared"&&k !in livePrepared)p+mapOf("state" to "unknown")else p}else emptyMap()
        fun times(field:String,ids:Set<String>)=DomainDtos.map(old[field]).filterKeys{it in ids}.mapValues{DomainDtos.map(DomainDtos.map(it.value)["stamp"])["server_observed_at"]}
        return mapOf("task_synced_at_by_id" to times("tasks_by_id",tasks.keys),"reminder_synced_at_by_id" to times("reminders_by_id",reminders.keys),"revision" to rev,"needs_sync" to (dashboard==null||ids.any{!tasks.containsKey(it)}),"dashboard" to dashboard,"tasks_by_id" to tasks,"reminders_by_id" to reminders,"pending_actions_by_key" to pending,"scope" to scope,"last_sync" to cached?.let{DomainDtos.map(it["stamp"])["server_observed_at"]})
    }
    fun clockChanged(){tickets.clear()
        val old=current()?:return
        storage.write(purge(old,DomainDtos.number(DomainDtos.map(old["scope"])["context_epoch"]),DomainDtos.number(DomainDtos.map(old["scope"])["owner_policy_version"])))
        dashboardEstablished=false}
    fun patch(patch:Map<String,Any?>,expected:Int){
        requirePermitted()
        check(verified&&dashboardEstablished)
        require(DomainJson.bytes(patch).size<=2097152)
        DomainDtos.exact(patch,"schema_version","upsert_pending","resolve_pending","invalidate_resources")
        require(patch["schema_version"]==1)
        val old=current()?:error("NO_SCOPE")
        checkRevision(old,expected)
        val pending=DomainDtos.map(old["pending_actions_by_key"]).toMutableMap()
        val tasks=DomainDtos.map(old["tasks_by_id"]).toMutableMap()
        val reminders=DomainDtos.map(old["reminders_by_id"]).toMutableMap()
        var floors=DomainEntityFloors.from(old)
        var invalidateDashboard=false
        for(raw in patch["upsert_pending"] as List<*>){val p=validatePending(raw)
            val key=p["action_key"] as String
            val prior=pending[key]?.let{DomainDtos.map(it)}
            if(prior!=null){check(prior.filterKeys{it!="state"}==p.filterKeys{it!="state"})
                check(p["state"]==prior["state"]||(p["state"]=="unknown"&&prior["state"] in setOf("prepared","unknown")))}
            else {check(p["state"]=="prepared"&&p["device_id"]==device&&DomainDtos.number(p["device_version"])==deviceVersion&&p["api_origin"]==origin&&DomainDtos.number(p["context_epoch"])==contextFloor)
                check(pending.values.none{val other=DomainDtos.map(it)
                    other["resource_id"]==p["resource_id"]&&other["state"] in setOf("prepared","unknown")})}
            pending[key]=p
        }
        for(raw in patch["resolve_pending"] as List<*>){val r=DomainDtos.map(raw)
            DomainDtos.exact(r,"action_key","resolution","source_operation","status_code","receipt","rejection")
            val key=DomainDtos.uuid(r["action_key"])
            val p=DomainDtos.map(pending[key])
            when(r["resolution"]){
                "confirmed_receipt"->{check(r["status_code"]==200&&r["rejection"]==null&&r["source_operation"] in setOf("getMutation",p["operation"]))
                    val receipt=DomainDtos.receipt(r["receipt"])
                    check(receipt["resource_id"]==p["resource_id"]&&receipt["resource_kind"]==(if(p["operation"]=="completeTask")"task"else"reminder")&&DomainDtos.number(receipt["version"])>DomainDtos.number(p["expected_version"]))

                    // The barrier is native and precedes publication; the previous durable
                    // unresolved record remains a read barrier if this candidate cannot fit.
                    tickets.supersedeAll()
                    invalidateDashboard=true
                    val primaryKind=if(receipt["resource_kind"]=="task")"tasks"else"reminders"
                    val primaryId=receipt["resource_id"] as String
                    val observedPrimary=(if(primaryKind=="tasks")tasks else reminders)[primaryId]?.let{DomainDtos.number(DomainDtos.map(DomainDtos.map(it)["dto"])["version"])}?:0
                    floors=DomainEntityFloors.advance(floors,primaryKind,primaryId,maxOf(observedPrimary,DomainDtos.number(receipt["version"])))
                    if(primaryKind=="tasks")tasks.remove(primaryId)else reminders.remove(primaryId)
                    if(receipt.containsKey("related_task_version")){
                        val related=reminderLinks[primaryId]
                        if(primaryKind=="reminders"&&related!=null){floors=DomainEntityFloors.advance(floors,"tasks",related,DomainDtos.number(receipt["related_task_version"]))
                            tasks.remove(related)}else tasks.clear()
                    }
                    if(receipt.containsKey("related_reminder_version")){
                        val related=reminderLinks.filterValues{it==primaryId}.keys.singleOrNull()
                        if(primaryKind=="tasks"&&related!=null){floors=DomainEntityFloors.advance(floors,"reminders",related,DomainDtos.number(receipt["related_reminder_version"]))
                            reminders.remove(related)}else reminders.clear()
                    }
                    pending[key]=p+mapOf("state" to "confirmed")}
                "definite_first_rejection"->{check(key in livePrepared&&p["state"]=="prepared"&&r["source_operation"]==p["operation"]&&r["receipt"]==null&&r["status_code"] in setOf(400,403,404,409,422,429))
                    val rejection=DomainDtos.map(r["rejection"])
                    DomainDtos.exact(rejection,"code")
                    require(rejection["code"] is String)
                    pending[key]=p+mapOf("state" to "rejected")}
                else->error("INVALID_RESOLUTION")}
        }
        for(raw in patch["invalidate_resources"] as List<*>){val r=DomainDtos.map(raw)
            DomainDtos.exact(r,"kind","id")
            val id=DomainDtos.uuid(r["id"])
            when(r["kind"]){"task"->tasks.remove(id)
                "reminder"->reminders.remove(id)
                else->error("INVALID_KIND")}}
        val next=DomainEntityFloors.put(old+mapOf("pending_actions_by_key" to pending,"tasks_by_id" to tasks,"reminders_by_id" to reminders,"dashboard" to (if(invalidateDashboard)null else old["dashboard"]),"revision" to revision(old)+1),floors)
        val protectedActions=(patch["resolve_pending"] as List<*>).map{DomainDtos.map(it)["action_key"] as String}.toSet()
        if(!admit(next,protectedActions))throw DomainFailure("DOMAIN_CAPACITY")
        for(raw in patch["upsert_pending"] as List<*>){val p=DomainDtos.map(raw)
            if(p["state"]=="prepared")livePrepared.add(p["action_key"] as String)}
    }
    private fun validatePending(raw:Any?):Map<String,Any?> {
        val p=DomainDtos.map(raw)
        DomainDtos.exact(p,"operation","resource_id","expected_version","delay_minutes","action_key","device_id","device_version","api_origin","context_epoch","canonical_request_hash","state")
        val op=DomainDtos.one(p["operation"],"completeTask","snoozeReminder")
        val resource=DomainDtos.uuid(p["resource_id"])
        val version=DomainDtos.number(p["expected_version"])
        require(if(op=="snoozeReminder")p["delay_minutes"]==10 else p["delay_minutes"]==null)
        DomainDtos.uuid(p["action_key"])
        DomainDtos.uuid(p["device_id"])
        DomainDtos.number(p["device_version"])
        DomainDtos.number(p["context_epoch"])
        DomainDtos.text(p["api_origin"],2048,1)
        DomainDtos.one(p["state"],"prepared","unknown","confirmed","rejected")
        val path=if(op=="completeTask")"/mobile/v1/tasks/$resource/complete"else"/mobile/v1/reminders/$resource/snooze"
        // Match Core's typed ExpectedVersion/SnoozeRequest canonical field order.
        val body=if(op=="snoozeReminder")"{\"expected_version\":$version,\"delay_minutes\":10}"else"{\"expected_version\":$version}"
        val canonical="POST\n$path\n$body"
        val hash=MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray(Charsets.UTF_8)).joinToString(""){"%02x".format(it)}
        require(p["canonical_request_hash"]==""||p["canonical_request_hash"]==hash)
        return p+mapOf("canonical_request_hash" to hash)
    }
}
