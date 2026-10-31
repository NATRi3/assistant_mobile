package io.github.natri3.assistant.security

// The domain slot has its own AAD; generic session writes never touch this file.
class PrivateCache(private val vault:SessionVault,private val origin:()->String,private val device:()->String,private val version:()->Long):DomainStorage {
 override fun read()=vault.readDomain(origin(),device(),version())
 override fun write(value:Map<String,Any?>)=vault.writeDomain(value,origin(),device(),version())
}
