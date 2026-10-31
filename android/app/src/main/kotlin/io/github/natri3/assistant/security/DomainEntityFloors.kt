package io.github.natri3.assistant.security

// Native-owned minimal consistency section. It has no text or freshness stamp.
object DomainEntityFloors {
    const val SECTION="entity_version_floors"
    fun empty():Map<String,Any?> = mapOf("schema_version" to 1,"tasks" to emptyMap<String,Any?>(),"reminders" to emptyMap<String,Any?>())
    fun from(document:Map<String,Any?>):Map<String,Any?> = DomainDtos.map(document["reserved_sections"])[SECTION]?.let{validate(it)}?:empty()
    fun validate(value:Any?):Map<String,Any?> {
        val section=DomainDtos.map(value)
        DomainDtos.exact(section,"schema_version","tasks","reminders")
        require(section["schema_version"]==1)
        for(kind in listOf("tasks","reminders"))for((id,version)in DomainDtos.map(section[kind])){DomainDtos.uuid(id)
            DomainDtos.number(version)}
        return section
    }
    fun check(section:Map<String,Any?>,kind:String,id:String,version:Long){
        val floor=DomainDtos.map(section[kind])[id]?.let{DomainDtos.number(it)}?:0
        check(version>=floor)
    }
    fun advance(section:Map<String,Any?>,kind:String,id:String,version:Long):Map<String,Any?> {
        val prior=DomainDtos.map(section[kind])
        val floor=prior[id]?.let{DomainDtos.number(it)}?:0
        return section+mapOf(kind to (prior+mapOf(id to maxOf(floor,version))))
    }
    // Called only on a newly accepted post-barrier read, after lower bodies/views
    // were atomically removed and all pre-effect tickets were invalidated.
    fun retire(section:Map<String,Any?>,kind:String,id:String,version:Long):Map<String,Any?> {
        check(section,kind,id,version)
        return section+mapOf(kind to DomainDtos.map(section[kind]).filterKeys{it!=id})
    }
    fun put(document:Map<String,Any?>,section:Map<String,Any?>)=document+mapOf("reserved_sections" to (DomainDtos.map(document["reserved_sections"])+mapOf(SECTION to section)))
}
