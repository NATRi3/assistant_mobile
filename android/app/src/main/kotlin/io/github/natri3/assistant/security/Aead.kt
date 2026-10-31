package io.github.natri3.assistant.security
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
object Aead {
 fun encrypt(key:SecretKey, plain:ByteArray,aad:ByteArray):ByteArray {
 val c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,key);c.updateAAD(aad);check(c.iv.size==12);return c.iv+c.doFinal(plain)
 }
 fun decrypt(key:SecretKey,bytes:ByteArray,aad:ByteArray):ByteArray {
 require(bytes.size>=28);val c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,key,GCMParameterSpec(128,bytes.copyOfRange(0,12)));c.updateAAD(aad);return c.doFinal(bytes.copyOfRange(12,bytes.size))
 }
}
