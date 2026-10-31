package io.github.natri3.assistant.security
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import com.nimbusds.jose.jwk.ECKey
import com.nimbusds.jose.jwk.Curve
class DeviceKeys(private val context:Context) {
 companion object {const val EC="assistant.device.ec.v1";const val AES="assistant.vault.aes.v1"}
 private fun store()=KeyStore.getInstance("AndroidKeyStore").apply{load(null)}
 fun secure():Boolean=context.getSystemService(KeyguardManager::class.java).isDeviceSecure
 private fun auth(b:KeyGenParameterSpec.Builder):KeyGenParameterSpec.Builder {
 b.setUserAuthenticationRequired(true)
 if(Build.VERSION.SDK_INT>=30) b.setUserAuthenticationParameters(300,KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL)
 else { @Suppress("DEPRECATION") b.setUserAuthenticationValidityDurationSeconds(300) }
 return b
 }
 fun ensure(){
 check(secure()){"SCREEN_LOCK_REQUIRED"};val s=store()
 check(s.containsAlias(EC)==s.containsAlias(AES)){"KEY_LOST"}
 if(!s.containsAlias(EC)){
 val generator=KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC,"AndroidKeyStore")
 generator.initialize(auth(KeyGenParameterSpec.Builder(EC,KeyProperties.PURPOSE_SIGN).setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1")).setDigests(KeyProperties.DIGEST_SHA256)).build());generator.generateKeyPair()
 try {val aes=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");aes.init(auth(KeyGenParameterSpec.Builder(AES,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setRandomizedEncryptionRequired(true)).build());aes.generateKey()}catch(e:Exception){destroy();throw e}
 }
 }
 fun privateKey():PrivateKey {check(secure());return store().getKey(EC,null) as? PrivateKey ?: error("KEY_LOST")}
 fun aes():SecretKey {check(secure());return store().getKey(AES,null) as? SecretKey ?: error("KEY_LOST")}
 fun publicJwk():ECKey = ECKey.Builder(Curve.P_256,store().getCertificate(EC)?.publicKey as? ECPublicKey ?: error("KEY_LOST")).build()
 fun fingerprint():String=publicJwk().computeThumbprint().toString()
 fun testAuthorization(){ val sig=java.security.Signature.getInstance("SHA256withECDSA");sig.initSign(privateKey());sig.update(byteArrayOf(1));sig.sign();val c=javax.crypto.Cipher.getInstance("AES/GCM/NoPadding");c.init(javax.crypto.Cipher.ENCRYPT_MODE,aes());c.doFinal(byteArrayOf(1)) }
 fun destroy(){val s=store();s.deleteEntry(EC);s.deleteEntry(AES)}
}
