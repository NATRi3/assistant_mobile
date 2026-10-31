package io.github.natri3.assistant.security

// Small JSON encoder shared by the exact plaintext budget and canonical hashes.
// Objects use sorted keys; strings retain UTF-8 and escape JSON control bytes.
object DomainJson {
    fun encode(v:Any?):String = when(v){
        null->"null"
        is String->buildString{append('"')
            v.forEach{c->when(c){'"'->append("\\\"")
                    '\\'->append("\\\\")
                    '\b'->append("\\b")
                    '\u000c'->append("\\f")
                    '\n'->append("\\n")
                    '\r'->append("\\r")
                    '\t'->append("\\t")
                    else->if(c<' ')append("\\u%04x".format(c.code))else append(c)}}
            append('"')}
        is Boolean->v.toString()
        is Int,is Long->v.toString()
        is Map<*,*>->v.keys.map{it as String}.sorted().joinToString(",","{","}"){encode(it)+":"+encode(v[it])}
        is List<*>->v.joinToString(",","[","]"){encode(it)}
        else->error("INVALID_JSON")
    }
    fun bytes(v:Any?)=encode(v).toByteArray(Charsets.UTF_8)
    @Suppress("UNCHECKED_CAST") fun copy(v:Any?):Any? = when(v){is Map<*,*>->v.entries.associate{it.key as String to copy(it.value)}
        is List<*>->v.map{copy(it)}
        else->v}
}
