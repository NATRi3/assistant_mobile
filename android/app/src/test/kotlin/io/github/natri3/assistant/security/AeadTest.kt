package io.github.natri3.assistant.security
import org.junit.Test
import org.junit.Assert.*
import javax.crypto.KeyGenerator
class AeadTest {
 @Test fun roundtripRandomIvAndTamperWrongAadWrongKeyFail(){
 val g=KeyGenerator.getInstance("AES");g.init(256);val key=g.generateKey();val plain="synthetic-secret".toByteArray();val aad="session|owned-key".toByteArray()
 val first=Aead.encrypt(key,plain,aad);val second=Aead.encrypt(key,plain,aad);assertFalse(first.contentEquals(second));assertArrayEquals(plain,Aead.decrypt(key,first,aad))
 for(work in listOf<()->Unit>({Aead.decrypt(key,first,"foreign".toByteArray())},{Aead.decrypt(g.generateKey(),first,aad)},{val changed=first.copyOf();changed[changed.lastIndex]=(changed.last().toInt() xor 1).toByte();Aead.decrypt(key,changed,aad)})) {assertTrue(runCatching(work).isFailure)}
 }
}
