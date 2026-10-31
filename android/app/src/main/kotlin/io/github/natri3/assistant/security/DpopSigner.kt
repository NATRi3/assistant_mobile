package io.github.natri3.assistant.security
import java.security.PrivateKey
import java.security.MessageDigest
import java.util.UUID
import java.util.Date
import java.util.Base64
import com.nimbusds.jose.*
import com.nimbusds.jose.jwk.ECKey
import com.nimbusds.jose.jwk.Curve
import com.nimbusds.jose.crypto.ECDSASigner
import com.nimbusds.jwt.JWTClaimsSet
import com.nimbusds.jwt.SignedJWT
class DpopSigner(private val key:PrivateKey,private val publicJwk:ECKey) {
 fun sign(method:String,uri:String,accessToken:String?,nowSeconds:Long):String {
 val claims=JWTClaimsSet.Builder().jwtID(UUID.randomUUID().toString()).issueTime(Date(nowSeconds*1000)).claim("htm",method).claim("htu",uri)
 if(accessToken!=null) claims.claim("ath",Base64.getUrlEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest(accessToken.toByteArray(Charsets.US_ASCII))))
 val jwt=SignedJWT(JWSHeader.Builder(JWSAlgorithm.ES256).type(JOSEObjectType("dpop+jwt")).jwk(publicJwk.toPublicJWK()).build(),claims.build())
 jwt.sign(ECDSASigner(key,Curve.P_256));return jwt.serialize()
 }
}
