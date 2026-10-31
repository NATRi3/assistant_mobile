package io.github.natri3.assistant.security
import org.junit.Test
import org.junit.Assert.*
import io.github.natri3.assistant.platform.*

class DomainCacheStoreTest {
    private val id="11111111-1111-4111-8111-111111111111"
    private val action="22222222-2222-4222-8222-222222222222"
    private val date="Sat, 31 Oct 2026 12:00:00 GMT"
    private var now=ClockSample(1,2,100,104)
    private var record:Map<String,Any?>?=null
    private val storage=object:DomainStorage{override fun read()=record
        override fun write(value:Map<String,Any?>){record=DomainDtos.map(DomainJson.copy(value))}}
    private fun store()=DomainStore(storage,object:DomainClock{override fun sample()=now},MemoryDomainAccessState()).also{it.bind("https://synthetic.invalid",id,1,7)}
    private fun device(context:Int=1)=mapOf("device_id" to id,"device_label" to "Synthetic","device_version" to 1,"state" to "active","fingerprint" to "A".repeat(43),"created_at" to "2026-10-31T12:00:00Z","registration_version" to 0,"context_epoch" to context)
    private fun prefs(policy:Int=1)=mapOf("version" to 1,"delivery_route" to "telegram","widget_summary_enabled" to false,"quiet_hours" to mapOf("enabled" to false,"start" to null,"end" to null,"timezone" to "UTC","owner_policy_version" to policy))
    private fun task(title:String="Synthetic",warning:Boolean=false)=mapOf("id" to id,"title" to title,"status" to "open","version" to 3,"due_date" to null,"due_at" to null,"source_warning" to warning,"updated_at" to "2026-10-31T12:00:00Z","permitted_actions" to listOf("complete"))
    private fun dashboard(context:Int=1)=mapOf("server_time" to "2026-10-31T12:00:00Z","snapshot_id" to id,"context_epoch" to context,"tasks" to listOf(task()),"total_open_count" to 1,"nearest_reminder" to null,"preferences" to prefs(),"next_cursor" to null)
    private fun rev()=(record?.get("revision") as? Number)?.toInt()?:0
    private fun verify(s:DomainStore,context:Int=1){val t=s.begin("getSelfDevice",null,null,0)
        s.commit(t.id,200,date,device(context),rev())}
    private fun sync(s:DomainStore){val t=s.begin("getDashboard",null,null,1)
        s.commit(t.id,200,date,dashboard(),rev())}
    private fun pending(key:String=action)=mapOf("operation" to "completeTask","resource_id" to id,"expected_version" to 3,"delay_minutes" to null,"action_key" to key,"device_id" to id,"device_version" to 1,"api_origin" to "https://synthetic.invalid","context_epoch" to 1,"canonical_request_hash" to "","state" to "prepared")
    private fun patch(upsert:List<Any?> = emptyList())=mapOf("schema_version" to 1,"upsert_pending" to upsert,"resolve_pending" to emptyList<Any?>(),"invalidate_resources" to emptyList<Any?>())
    @Test fun writerActuallyPersistsAndMetadataDoesNotReplaceOtherSections(){
        val s=store()
        verify(s)
        sync(s)
        assertNotNull("Deferred native writer must actually persist an envelope",record)
        record=record!!+mapOf("reserved_sections" to mapOf("future" to mapOf("schema_version" to 1,"turns" to emptyList<Any?>(),"opaque" to "synthetic-reserved")))
        val original=DomainDtos.map(record!!["reserved_sections"])["future"]
        s.patch(patch(listOf(pending())),rev())
        assertEquals(original,DomainDtos.map(record!!["reserved_sections"])["future"])
        assertNotNull(DomainDtos.map(s.frame()["pending_actions_by_key"])[action])
        s.patch(patch(),rev())
        assertEquals(original,DomainDtos.map(record!!["reserved_sections"])["future"])
        assertEquals(1,DomainDtos.map(record!!["pending_actions_by_key"]).size)
    }
    @Test fun casDoesNotRenewTicketOrAgeAndColdEpochCannotReveal(){
        val s=store()
        verify(s)
        sync(s)
        val t=s.begin("getTask",id,null,0)
        s.patch(patch(),rev())
        val stale=rev()-1
        assertEquals("DOMAIN_REVISION_CONFLICT",(runCatching{s.commit(t.id,200,date,task(),stale)}.exceptionOrNull() as DomainFailure).code)
        now=now.copy(elapsed=5001)
        assertTrue(runCatching{s.commit(t.id,200,date,task(),rev())}.isFailure)
        val fresh=store()
        assertNull(fresh.frame()["dashboard"])
        verify(fresh)
        assertNotNull(fresh.frame()["dashboard"])
        now=now.copy(elapsed=86400001)
        assertNull(fresh.frame()["dashboard"])
        assertTrue(DomainDtos.map(record!!["tasks_by_id"]).isNotEmpty())
    }
    @Test fun higherSelfFloorPurgesBeforeFallbackAndRestoredPendingNeedsFreshDashboard(){
        val s=store()
        verify(s)
        sync(s)
        s.patch(patch(listOf(pending())),rev())
        val fresh=store()
        verify(fresh,2)
        assertNull(fresh.frame()["dashboard"])
        assertTrue(DomainDtos.map(fresh.frame()["pending_actions_by_key"]).isEmpty())
        assertEquals(1,DomainDtos.map(record!!["pending_actions_by_key"]).size)
    }
    @Test fun equalEntityVersionStableFieldsFailDerivedFieldsMayChange(){
        val s=store()
        verify(s)
        sync(s)
        now=now.copy(elapsed=2)
        val t=s.begin("getTask",id,null,0)
        s.commit(t.id,200,date,task(warning=true),rev())
        now=now.copy(elapsed=3)
        val bad=s.begin("getTask",id,null,0)
        assertTrue(runCatching{s.commit(bad.id,200,date,task(title="changed"),rev())}.isFailure)
    }
    @Test fun capacityAndMutationImmutabilityPreserveCommittedState(){
        val s=store()
        verify(s)
        sync(s)
        s.patch(patch(listOf(pending())),rev())
        val stable=record
        assertTrue(runCatching{s.patch(patch(listOf(pending()+mapOf("expected_version" to 4))),rev())}.isFailure)
        assertEquals(stable,record)
        record=record!!+mapOf("reserved_sections" to mapOf("future" to mapOf("schema_version" to 1,"turns" to emptyList<Any?>(),"opaque" to "x".repeat(2096000))))
        val prior=record
        val failure=runCatching{s.patch(patch(listOf(pending("33333333-3333-4333-8333-333333333333")+mapOf("resource_id" to "44444444-4444-4444-8444-444444444444"))),rev())}.exceptionOrNull()
        assertNotNull(failure)
        assertEquals(prior,record)
    }
    private fun resolve(version:Int=5)=mapOf("schema_version" to 1,"upsert_pending" to emptyList<Any?>(),"resolve_pending" to listOf(mapOf("action_key" to action,"resolution" to "confirmed_receipt","source_operation" to "getMutation","status_code" to 200,"receipt" to mapOf("effect_id" to action,"resource_id" to id,"resource_kind" to "task","version" to version,"changed_at" to "2026-10-31T12:01:00Z","replayed" to false),"rejection" to null)),"invalidate_resources" to emptyList<Any?>())
    @Test fun confirmedEffectRejectsDelayedDetailAndLowerSummaryAndRetiresOnlyAfterFreshEntity(){
        val s=store()
        verify(s)
        sync(s)
        s.patch(patch(listOf(pending())),rev())
        val old=s.begin("getTask",id,null,0)
        s.patch(resolve(),rev())
        assertNull("Receipt must invalidate the cached dashboard",s.frame()["dashboard"])
        assertTrue("A pre-effect ticket must never restore an old entity",runCatching{s.commit(old.id,200,date,task(),rev())}.isFailure)
        val floors=DomainDtos.map(DomainDtos.map(record!!["reserved_sections"])["entity_version_floors"])
        assertEquals(5L,DomainDtos.map(floors["tasks"])[id])
        val low=s.begin("getTask",id,null,0)
        assertTrue(runCatching{s.commit(low.id,200,date,task(),rev())}.isFailure)
        now=now.copy(elapsed=3)
        val fresh=s.begin("getTask",id,null,0)
        s.commit(fresh.id,200,date,task()+mapOf("version" to 5),rev())
        assertTrue(DomainDtos.map(DomainDtos.map(DomainDtos.map(record!!["reserved_sections"])["entity_version_floors"])["tasks"]).isEmpty())
    }
    @Test fun durableUnresolvedRecordBlocksOldBodiesAfterFailedResolutionAndRestart(){
        val s=store()
        verify(s)
        sync(s)
        s.patch(patch(listOf(pending())),rev())
        val restored=store()
        verify(restored)
        assertNull("Unresolved metadata is the durable crash-safe fallback barrier",restored.frame()["dashboard"])
        assertTrue(DomainDtos.map(restored.frame()["tasks_by_id"]).isEmpty())
        assertEquals(1,DomainDtos.map(record!!["pending_actions_by_key"]).size)
    }

    @Test fun competingPatchCasRemergePreservesBothIntentsAndFutureSection(){
        val s=store()
        verify(s)
        sync(s)
        record=record!!+mapOf("reserved_sections" to mapOf("future" to mapOf("schema_version" to 1,"turns" to listOf("synthetic"))))
        val sharedRevision=rev()
        s.patch(patch(listOf(pending())),sharedRevision)
        val second=pending("33333333-3333-4333-8333-333333333333")+mapOf("resource_id" to "44444444-4444-4444-8444-444444444444")
        assertEquals("DOMAIN_REVISION_CONFLICT",(runCatching{s.patch(patch(listOf(second)),sharedRevision)}.exceptionOrNull() as DomainFailure).code)
        s.patch(patch(listOf(second)),rev())
        assertEquals(2,DomainDtos.map(record!!["pending_actions_by_key"]).size)
        assertNotNull(DomainDtos.map(record!!["reserved_sections"])["future"])
    }
    @Test fun relatedIdUsesOnlyCurrentReminderLinkOtherwiseInvalidatesFamily(){
        for(known in listOf(false,true)){
            record=null
            now=ClockSample(1,2,100,104)
            val s=store()
            verify(s)
            sync(s)
            val reminder=mapOf("id" to action,"text" to "Synthetic reminder","status" to "scheduled","active" to true,"version" to 4,"due_at" to "2026-10-31T13:00:00Z","timezone" to "UTC","linked_task_id" to id,"source_warning" to false,"updated_at" to "2026-10-31T12:00:00Z","permitted_actions" to listOf("snooze_10m"))
            if(known){val t=s.begin("getReminder",action,null,0)
                s.commit(t.id,200,date,reminder,rev())}
            s.patch(patch(listOf(pending())),rev())
            val resolution=resolve()
            val r=DomainDtos.map((resolution["resolve_pending"] as List<*>).single())
            val receipt=DomainDtos.map(r["receipt"])+mapOf("related_reminder_version" to 9)
            s.patch(resolution+mapOf("resolve_pending" to listOf(r+mapOf("receipt" to receipt))),rev())
            val floors=DomainDtos.map(DomainEntityFloors.from(record!!)["reminders"])
            assertEquals(if(known)9L else null,floors[action])
            assertTrue(DomainDtos.map(record!!["reminders_by_id"]).isEmpty())
            assertNull(record!!["dashboard"])
        }
    }
    @Test fun olderReplayCannotRegressObservedEntityAndFloorHasNoSyncStamp(){
        val s=store()
        verify(s)
        sync(s)
        s.patch(patch(listOf(pending())),rev())
        s.patch(resolve(),rev())
        now=now.copy(elapsed=3)
        val t=s.begin("getTask",id,null,0)
        s.commit(t.id,200,date,task()+mapOf("version" to 10),rev())
        s.patch(resolve(),rev())
        val floors=DomainEntityFloors.from(record!!)
        assertEquals(10L,DomainDtos.map(floors["tasks"])[id])
        assertEquals(setOf("schema_version","tasks","reminders"),floors.keys)
    }
    @Test fun floorQuotaFailureKeepsUnresolvedBarrierAcrossRestart(){
        val s=store()
        verify(s)
        sync(s)
        s.patch(patch(listOf(pending())),rev())
        // No replaceable bodies remain; protected future metadata uses the remaining budget.
        record=record!!+mapOf("dashboard" to null,"tasks_by_id" to emptyMap<String,Any?>(),"reminders_by_id" to emptyMap<String,Any?>(),"reserved_sections" to mapOf("future" to mapOf("schema_version" to 1,"turns" to emptyList<Any?>(),"opaque" to "")))
        val space=2097152-DomainJson.bytes(record).size
        record=record!!+mapOf("reserved_sections" to mapOf("future" to mapOf("schema_version" to 1,"turns" to emptyList<Any?>(),"opaque" to "x".repeat(space))))
        val before=record
        val failure=runCatching{s.patch(resolve(),rev())}.exceptionOrNull()
        assertEquals("DOMAIN_CAPACITY",(failure as DomainFailure).code)
        assertEquals(before,record)
        val fresh=store()
        verify(fresh)
        assertNull(fresh.frame()["dashboard"])
        assertTrue(DomainDtos.map(fresh.frame()["tasks_by_id"]).isEmpty())
        assertEquals("prepared",DomainDtos.map(DomainDtos.map(record!!["pending_actions_by_key"])[action])["state"])
    }

    @Test fun unknownBootAcceptsCurrentOnlineVerificationButNeverPrivateOfflineAge(){
        now=now.copy(boot=-1)
        val s=store()
        verify(s)
        val t=s.begin("getDashboard",null,null,1)
        val ack=s.commit(t.id,200,date,dashboard(),rev())
        assertEquals(false,ack["cached"])
        assertNull(s.frame()["dashboard"])
    }

    @Test fun nativeCanonicalHashMatchesCoreTypedBodyAndRejectsChangedIntent(){
        val s=store()
        verify(s)
        sync(s)
        s.patch(patch(listOf(pending())),rev())
        val original=DomainDtos.map(DomainDtos.map(record!!["pending_actions_by_key"])[action])
        assertEquals("60bf2d95cc64471481dad2f5e5df714b56d8fc7b31e34d5f5cd0f3cb5840d391",original["canonical_request_hash"])
        val before=record
        for(changed in listOf(pending()+mapOf("operation" to "snoozeReminder","delay_minutes" to 10),pending()+mapOf("resource_id" to "44444444-4444-4444-8444-444444444444"),pending()+mapOf("expected_version" to 4))){assertTrue(runCatching{s.patch(patch(listOf(changed)),rev())}.isFailure)
            assertEquals(before,record)}
        record=null
        val snooze=store()
        verify(snooze)
        sync(snooze)
        snooze.patch(patch(listOf(pending()+mapOf("operation" to "snoozeReminder","delay_minutes" to 10))),rev())
        assertEquals("6be9bccd550c2037862365f8a65625b2ad335eab2159c3286495902f0ac972c1",DomainDtos.map(DomainDtos.map(record!!["pending_actions_by_key"])[action])["canonical_request_hash"])
    }

    @Test fun higherDeviceContextDiscardsPreviouslyProvenRelatedIdentity(){
        val s=store();verify(s);sync(s)
        val reminder=mapOf("id" to action,"text" to "Synthetic reminder","status" to "scheduled","active" to true,"version" to 4,"due_at" to "2026-10-31T13:00:00Z","timezone" to "UTC","linked_task_id" to id,"source_warning" to false,"updated_at" to "2026-10-31T12:00:00Z","permitted_actions" to listOf("snooze_10m"))
        val r=s.begin("getReminder",action,null,0);s.commit(r.id,200,date,reminder,rev())
        verify(s,2);val d=s.begin("getDashboard",null,null,2);s.commit(d.id,200,date,dashboard(2),rev())
        s.patch(patch(listOf(pending()+mapOf("context_epoch" to 2))),rev())
        val resolution=resolve();val item=DomainDtos.map((resolution["resolve_pending"] as List<*>).single())
        s.patch(resolution+mapOf("resolve_pending" to listOf(item+mapOf("receipt" to (DomainDtos.map(item["receipt"])+mapOf("related_reminder_version" to 9))))),rev())
        assertTrue("An old context link is not current proof of related identity",DomainDtos.map(DomainEntityFloors.from(record!!)["reminders"]).isEmpty())
    }

    @Test fun taskAdmissionCeiling200DoesNotRewriteServerTotalOrAge(){
        val s=store();verify(s)
        var cursor:String?=null
        for(page in 0..4){
            now=now.copy(elapsed=page.toLong()+1)
            val count=if(page==4)1 else 50
            val items=(0 until count).map{index->task()+mapOf("id" to "%08x-1111-4111-8111-111111111111".format(page*50+index))}
            val next=if(page==4)null else "cursor-${page+1}"
            val t=s.begin("getDashboard",null,cursor,1)
            val ack=s.commit(t.id,200,date,dashboard()+mapOf("tasks" to items,"total_open_count" to 201,"next_cursor" to next),rev())
            if(page==4)assertEquals(false,ack["cached"])
            cursor=next
        }
        assertEquals(200,DomainDtos.map(record!!["tasks_by_id"]).size)
        val header=DomainDtos.map(DomainDtos.map(record!!["dashboard"])["header"])
        assertEquals(201,header["total_open_count"])
        assertEquals(1L,DomainDtos.map(DomainDtos.map(record!!["dashboard"])["stamp"])["sync_elapsed_ms"])
    }

    @Test fun reviewR1DenialSurvivesReopenAndDeviceOnlyVerification(){
        val access=MemoryDomainAccessState()
        fun open()=DomainStore(storage,object:DomainClock{override fun sample()=now},access).also{it.bind("https://synthetic.invalid",id,1,7)}
        val s=open();verify(s);sync(s);s.denyAccess();assertTrue(access.denied);assertNull(s.frame()["dashboard"])
        for(operation in listOf("getTask","getReminder","completeTask","snoozeReminder","getMutation"))assertEquals("DOMAIN_ACCESS_DENIED",(runCatching{s.requireOperation(operation)}.exceptionOrNull() as DomainFailure).code)
        for(operation in listOf("getSelfDevice","getDashboard","revokeSelfDevice","refreshSession"))s.requireOperation(operation)
        val fresh=open();verify(fresh);assertNull(fresh.frame()["dashboard"])
        val t=fresh.begin("getDashboard",null,null,2);fresh.commit(t.id,200,date,dashboard(),rev());assertFalse(access.denied);assertNotNull(fresh.frame()["dashboard"])
    }
    @Test fun reviewR4KnownSupersededReadIsTypedAndCannotStamp(){
        val s=store();verify(s);sync(s);val t=s.begin("getTask",id,null,0);s.begin("getDashboard",null,null,2)
        val before=record
        assertTrue(runCatching{s.commit(t.id,200,date,task(),rev())}.exceptionOrNull() is DomainReadSuperseded)
        assertEquals(before,record)
        assertFalse(runCatching{s.commit("foreign",200,date,task(),rev())}.exceptionOrNull() is DomainReadSuperseded)
    }

    @Test fun reviewR3TerminalDetailCannotLeaveOldOpenMembership(){
        val s=store();verify(s);sync(s);val t=s.begin("getTask",id,null,0)
        s.commit(t.id,200,date,task()+mapOf("version" to 4,"status" to "done","permitted_actions" to emptyList<Any?>()),rev())
        assertNull("Old count/membership cannot remain an eligible Dashboard",s.frame()["dashboard"])
        assertEquals("done",DomainDtos.map(DomainDtos.map(s.frame()["tasks_by_id"])[id])["status"])
    }
    @Test fun reviewR3ReminderDetailCannotLeaveObsoleteNearestSummary(){
        val s=store();verify(s)
        val d=s.begin("getDashboard",null,null,1)
        s.commit(d.id,200,date,dashboard()+mapOf("nearest_reminder" to mapOf("id" to action,"due_at" to "2026-10-31T13:00:00Z","version" to 4,"source_warning" to false)),rev())
        val t=s.begin("getReminder",action,null,0)
        s.commit(t.id,200,date,mapOf("id" to action,"text" to "Synthetic","status" to "scheduled","active" to true,"version" to 5,"due_at" to "2026-10-31T14:00:00Z","timezone" to "UTC","linked_task_id" to null,"source_warning" to true,"updated_at" to "2026-10-31T12:00:00Z","permitted_actions" to listOf("snooze_10m")),rev())
        assertNull(s.frame()["dashboard"])
    }

    @Test fun reviewR4MalformedForeignExpiredAndEpochRemainFailures(){
        val s=store();verify(s);sync(s);val t=s.begin("getTask",id,null,0);s.begin("getDashboard",null,null,2)
        for(body in listOf(emptyMap<String,Any?>(),task()+mapOf("id" to action),task()+mapOf("owner_id" to "foreign"))){val error=runCatching{s.commit(t.id,200,date,body,rev())}.exceptionOrNull();assertNotNull(error);assertFalse(error is DomainReadSuperseded)}
        assertFalse(runCatching{s.commit(t.id,204,date,task(),rev())}.exceptionOrNull() is DomainReadSuperseded)
        now=now.copy(elapsed=5001);assertFalse(runCatching{s.commit(t.id,200,date,task(),rev())}.exceptionOrNull() is DomainReadSuperseded)
        s.bind("https://synthetic.invalid",id,1,8);assertFalse(runCatching{s.commit(t.id,200,date,task(),rev())}.exceptionOrNull() is DomainReadSuperseded)
    }
    @Test fun reviewR3QuotaCannotRestoreOlderAcceptedPrivateCopy(){
        val s=store();verify(s);sync(s)
        record=record!!+mapOf("reserved_sections" to mapOf("future" to mapOf("schema_version" to 1,"opaque" to "")))
        val space=2097152-DomainJson.bytes(record).size-512
        record=record!!+mapOf("reserved_sections" to mapOf("future" to mapOf("schema_version" to 1,"opaque" to "x".repeat(space))))
        val t=s.begin("getTask",id,null,0);val ack=s.commit(t.id,200,date,task(title="x".repeat(4096))+mapOf("version" to 4),rev())
        assertEquals(false,ack["cached"]);assertNull(s.frame()["dashboard"]);assertTrue(DomainDtos.map(s.frame()["tasks_by_id"]).isEmpty())
        val fresh=store();verify(fresh);assertNull(fresh.frame()["dashboard"]);assertTrue(DomainDtos.map(fresh.frame()["tasks_by_id"]).isEmpty())
    }
    @Test fun reviewR4OldActivePageCannotUndoFreshDetailOrDerivedPolicy(){
        val s=store();verify(s);sync(s);val old=s.begin("getDashboard",null,null,2)
        val detail=s.begin("getTask",id,null,0);s.commit(detail.id,200,date,task(title="scrubbed",warning=true)+mapOf("version" to 4),rev())
        assertTrue(runCatching{s.commit(old.id,200,date,dashboard(),rev())}.exceptionOrNull() is DomainReadSuperseded)
        assertEquals("scrubbed",DomainDtos.map(DomainDtos.map(s.frame()["tasks_by_id"])[id])["title"])
    }

    @Test fun reviewR3bReminderAdmissionFencesAllOlderSummaryVariants(){
        for(variant in listOf("version","warning","terminal")){
            record=null;now=ClockSample(1,2,100,104);val s=store();verify(s)
            val summary=mapOf("id" to action,"due_at" to "2026-10-31T13:00:00Z","version" to 4,"source_warning" to false)
            val initial=s.begin("getDashboard",null,null,1);s.commit(initial.id,200,date,dashboard()+mapOf("nearest_reminder" to summary),rev())
            val older=s.begin("getDashboard",null,null,2);now=now.copy(elapsed=2)
            val body=mapOf("id" to action,"text" to "Synthetic","status" to (if(variant=="terminal")"cancelled"else"scheduled"),"active" to (variant!="terminal"),"version" to (if(variant=="warning")4 else 5),"due_at" to (if(variant=="version")"2026-10-31T14:00:00Z"else"2026-10-31T13:00:00Z"),"timezone" to "UTC","linked_task_id" to null,"source_warning" to (variant=="warning"),"updated_at" to "2026-10-31T12:00:00Z","permitted_actions" to (if(variant=="terminal")emptyList()else listOf("snooze_10m")))
            val detail=s.begin("getReminder",action,null,0);s.commit(detail.id,200,date,body,rev());val accepted=record
            assertTrue("Obsolete summary must be a healthy typed drop",runCatching{s.commit(older.id,200,date,dashboard()+mapOf("nearest_reminder" to summary),rev())}.exceptionOrNull() is DomainReadSuperseded)
            assertEquals(accepted,record);assertNull(s.frame()["dashboard"])
            now=now.copy(elapsed=4);val fresh=s.begin("getDashboard",null,null,3)
            val latest=if(variant=="terminal")null else mapOf("id" to action,"due_at" to body["due_at"],"version" to body["version"],"source_warning" to body["source_warning"])
            s.commit(fresh.id,200,date,dashboard()+mapOf("nearest_reminder" to latest),rev())
            assertEquals(latest,DomainDtos.map(s.frame()["dashboard"])["nearest_reminder"])
            val stamp=DomainDtos.map(DomainDtos.map(DomainDtos.map(record!!["reminders_by_id"])[action])["stamp"])
            assertEquals(2L,stamp["sync_elapsed_ms"])
            assertTrue(DomainDtos.map(DomainEntityFloors.from(record!!)["reminders"]).isEmpty())
        }
    }

}
