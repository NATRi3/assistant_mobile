package io.github.natri3.assistant
import android.app.Activity
import android.app.KeyguardManager
import android.content.*
import android.os.*
import android.view.*
import android.widget.TextView
import android.graphics.Color
import androidx.biometric.BiometricPrompt
import androidx.biometric.BiometricManager.Authenticators
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.github.natri3.assistant.platform.PlatformBridge
class MainActivity:FlutterFragmentActivity() {
 private lateinit var bridge:PlatformBridge
 private var cover:TextView?=null
 private var success:(()->Unit)?=null;private var failure:(()->Unit)?=null
 private var credentialPending=false;private var credentialResult=false;private var challengePause=false
 private val handler=Handler(Looper.getMainLooper());private var prompt:BiometricPrompt?=null
 private val timeout=Runnable{cancelChallenge()}
 private val lockReceiver=object:BroadcastReceiver(){override fun onReceive(c:Context?,i:Intent?){cancelChallenge();if(::bridge.isInitialized){if(i?.action==Intent.ACTION_TIME_CHANGED)bridge.clockChanged()else bridge.lock()}}}
 override fun onCreate(savedInstanceState:Bundle?){
 window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
 super.onCreate(savedInstanceState)
 val filter=IntentFilter(Intent.ACTION_SCREEN_OFF).apply{addAction(Intent.ACTION_TIME_CHANGED)}
 if(Build.VERSION.SDK_INT>=33)registerReceiver(lockReceiver,filter,Context.RECEIVER_NOT_EXPORTED)else registerReceiver(lockReceiver,filter)
 }
 override fun configureFlutterEngine(engine:FlutterEngine){super.configureFlutterEngine(engine)
 bridge=PlatformBridge(this,MethodChannel(engine.dartExecutor.binaryMessenger,"assistant.platform/v1"),::authenticate,::showCover,::hideCover)
 }
 private fun showCover(){
 if(cover==null){cover=TextView(this).apply{text="Ассистент заблокирован";setTextColor(Color.WHITE);setBackgroundColor(Color.rgb(16,28,24));gravity=Gravity.CENTER;importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_YES}
 addContentView(cover,ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,ViewGroup.LayoutParams.MATCH_PARENT))}
 cover?.visibility=View.VISIBLE
 }
 private fun hideCover(){cover?.visibility=View.GONE}
 private fun authenticate(ok:()->Unit,fail:()->Unit){
 success=ok;failure=fail;handler.postDelayed(timeout,60000)
 if(Build.VERSION.SDK_INT<30){
 val km=getSystemService(KeyguardManager::class.java)
 @Suppress("DEPRECATION") val intent=km.createConfirmDeviceCredentialIntent("Ассистент","Откройте защищённую сессию")
 if(intent==null){cancelChallenge();return};credentialPending=true;challengePause=true
 @Suppress("DEPRECATION") startActivityForResult(intent.addFlags(Intent.FLAG_ACTIVITY_NO_USER_ACTION),4921)
 }else{
 prompt=BiometricPrompt(this,ContextCompat.getMainExecutor(this),object:BiometricPrompt.AuthenticationCallback(){
 override fun onAuthenticationSucceeded(result:BiometricPrompt.AuthenticationResult){completeChallenge()}
 override fun onAuthenticationError(code:Int,message:CharSequence){cancelChallenge()}
 })
 challengePause=true
 prompt!!.authenticate(BiometricPrompt.PromptInfo.Builder().setTitle("Разблокировать ассистента").setAllowedAuthenticators(Authenticators.BIOMETRIC_STRONG or Authenticators.DEVICE_CREDENTIAL).build())
 }
 }
 private fun completeChallenge(){handler.removeCallbacks(timeout);val cb=success;success=null;failure=null;credentialPending=false;credentialResult=false;challengePause=false;cb?.invoke()}
 private fun cancelChallenge(){handler.removeCallbacks(timeout);val cb=failure;success=null;failure=null;credentialPending=false;credentialResult=false;challengePause=false;prompt?.cancelAuthentication();prompt=null;cb?.invoke()}
 @Deprecated("Legacy Keyguard credential challenge is required on API28/29")
 override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?){super.onActivityResult(requestCode,resultCode,data)
 if(requestCode==4921){if(credentialPending&&resultCode==Activity.RESULT_OK)credentialResult=true else cancelChallenge()}
 }
 override fun onPostResume(){super.onPostResume();if(::bridge.isInitialized)bridge.resume();if(credentialResult)completeChallenge()}
 override fun onPause(){showCover();if(::bridge.isInitialized)bridge.pause();if(challengePause)challengePause=false else cancelChallenge();super.onPause()}
 override fun onUserLeaveHint(){cancelChallenge();super.onUserLeaveHint()}
 override fun onDestroy(){cancelChallenge();unregisterReceiver(lockReceiver);super.onDestroy()}
}
