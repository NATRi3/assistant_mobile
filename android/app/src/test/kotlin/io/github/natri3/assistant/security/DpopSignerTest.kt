package io.github.natri3.assistant.security
import org.junit.Test
import org.junit.Assert.*
import java.security.KeyPairGenerator
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.MessageDigest
import java.util.Base64
import com.nimbusds.jose.jwk.ECKey
import com.nimbusds.jose.jwk.Curve
import com.nimbusds.jwt.SignedJWT
import com.nimbusds.jose.crypto.ECDSAVerifier
class DpopSignerTest {
 @Test fun standardProofVerifiesAndBindsRequest() {
 val g=KeyPairGenerator.getInstance("EC"); g.initialize(ECGenParameterSpec("secp256r1")); val pair=g.generateKeyPair()
 val jwk=ECKey.Builder(Curve.P_256,pair.public as ECPublicKey).build()
 val signer=DpopSigner(pair.private,jwk)
 val compact=signer.sign("GET","https://mobile.example.invalid/mobile/v1/devices/self","A".repeat(43),1793448000)
 assertEquals("A compact signed JWT has three segments",3,compact.split('.').size)
 val jwt=SignedJWT.parse(compact)
 assertTrue(jwt.verify(ECDSAVerifier(jwk))); assertEquals("dpop+jwt",jwt.header.type.type); assertEquals("ES256",jwt.header.algorithm.name)
 assertNull(jwt.header.jwk.toJSONObject()["d"])
 val c=jwt.jwtClaimsSet; assertEquals("GET",c.getStringClaim("htm")); assertEquals("https://mobile.example.invalid/mobile/v1/devices/self",c.getStringClaim("htu"))
 assertEquals(1793448000000,c.issueTime.time); assertEquals(4,java.util.UUID.fromString(c.jwtid).version())
 val ath=Base64.getUrlEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest("A".repeat(43).toByteArray(Charsets.US_ASCII)))
 assertEquals(ath,c.getStringClaim("ath"))
 val next=SignedJWT.parse(signer.sign("POST","https://mobile.example.invalid/mobile/v1/pairings",null,1793448000))
 assertNotEquals(c.jwtid,next.jwtClaimsSet.jwtid); assertNull(next.jwtClaimsSet.getClaim("ath"))
 }
}
