package io.github.natri3.assistant.security

import android.app.KeyguardManager
import android.os.Build
import android.os.SystemClock
import android.view.KeyEvent
import android.view.WindowManager
import android.view.accessibility.AccessibilityNodeInfo
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.natri3.assistant.BuildConfig
import io.github.natri3.assistant.MainActivity
import io.github.natri3.assistant.platform.ForegroundGate
import io.github.natri3.assistant.platform.PlatformBridge
import java.io.Closeable
import java.io.File
import java.security.KeyStore
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import org.junit.Assert.*

/** Only owns a newly installed synthetic application on this lane's disposable AVD. */
class NativeDeviceHarness : Closeable {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    val context = instrumentation.targetContext
    val keys = DeviceKeys(context)
    val vault = SessionVault(context, keys)
    private var scenario: ActivityScenario<MainActivity>? = null
    private lateinit var bridge: PlatformBridge
    private var owned = false
    private var unlockObservation: NativeUnlockObservation? = null
    private var diagnosticPhase = "NATIVE_REQUEST"
    private var diagnosticCode = "NO_UNLOCK_REQUEST"
    private var diagnosticRoot = "NOT_SAMPLED"
    private var diagnosticIds = emptyList<String>()
    private var diagnosticViewIds = false

    fun openFreshActivity() {
        check(InstrumentationRegistry.getArguments().getString("synthetic_emulator") == "true") { "SYNTHETIC_MODE_REQUIRED" }
        check(Build.VERSION.SDK_INT == 36 && Build.SUPPORTED_ABIS.first() == "x86_64" && Build.HARDWARE == "ranchu") { "UNEXPECTED_DEVICE" }
        val qemu = instrumentation.uiAutomation.executeShellCommand("getprop ro.kernel.qemu").use {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(it).bufferedReader().readText().trim()
        }
        check(qemu == "1") { "EMULATOR_REQUIRED" }
        check(context.packageName == "io.github.natri3.assistant" && BuildConfig.ASSISTANT_API_ORIGIN.isEmpty()) { "UNEXPECTED_APP" }
        synchronized(installation) {
            if (!installationChecked) {
                val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                check(!store.containsAlias(DeviceKeys.EC) && !store.containsAlias(DeviceKeys.AES)) { "INSTALL_NOT_FRESH" }
                check(vaultFiles().none { it.exists() }) { "INSTALL_NOT_FRESH" }
                check(context.getSharedPreferences("public-device-state", 0).all.isEmpty()) { "INSTALL_NOT_FRESH" }
                installationChecked = true
            }
        }
        owned = true
        prepareInitialDevice()
        scenario = ActivityScenario.launch(MainActivity::class.java)
        acquireBridge()
        assertLocked()
    }

    private fun prepareInitialDevice() {
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        check(keys.secure()) { "INITIAL_SCREEN_LOCK_REQUIRED" }
        if (keyguard.isKeyguardLocked) {
            // OS setup only: this neither requests a bridge unlock nor opens its gate.
            press(KeyEvent.KEYCODE_WAKEUP)
            // Request the system bouncer, then require its recognized PIN UI before input.
            // Close the output immediately; no shell output, hierarchy or field text is logged.
            instrumentation.uiAutomation.executeShellCommand("wm dismiss-keyguard").close()
            try {
                enterSyntheticCredential()
            } catch (_: Exception) {
                error("INITIAL_OS_CREDENTIAL_UI_UNAVAILABLE")
            }
            val deadline = SystemClock.elapsedRealtime() + 10000
            while (keyguard.isKeyguardLocked && SystemClock.elapsedRealtime() < deadline) {
                SystemClock.sleep(100)
            }
        }
        check(keys.secure()) { "INITIAL_SCREEN_LOCK_REQUIRED" }
        check(!keyguard.isKeyguardLocked) { "INITIAL_DEVICE_STILL_LOCKED" }
    }

    private fun acquireBridge() {
        scenario!!.onActivity { activity ->
            assertTrue("FLAG_SECURE_REQUIRED", activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0)
            val field = MainActivity::class.java.getDeclaredField("bridge").apply { isAccessible = true }
            bridge = field.get(activity) as? PlatformBridge ?: error("BRIDGE_CONTRACT_CHANGED")
        }
    }

    private fun beginCall(method: String, arguments: Any?): CompletableFuture<NativeResult> {
        val future = CompletableFuture<NativeResult>()
        if (method == "unlockAndReadSession") {
            recordNativeResult("NATIVE_REQUEST", "PENDING")
            unlockObservation = NativeUnlockObservation(future, ::recordNativeResult)
        }
        instrumentation.runOnMainSync {
            bridge.onMethodCall(MethodCall(method, arguments), object : MethodChannel.Result {
                override fun success(value: Any?) { check(future.complete(NativeResult(value, null))) { "DUPLICATE_NATIVE_RESULT" } }
                override fun error(code: String, message: String?, details: Any?) { check(future.complete(NativeResult(null, code))) { "DUPLICATE_NATIVE_RESULT" } }
                override fun notImplemented() { future.complete(NativeResult(null, "NOT_IMPLEMENTED")) }
            })
        }
        return future
    }

    fun call(method: String, arguments: Any?): NativeResult = beginCall(method, arguments).get(10, TimeUnit.SECONDS)
    fun beginUnlock(): CompletableFuture<NativeResult> = beginCall("unlockAndReadSession", null)

    private val systemPackages = setOf("com.android.settings", "com.android.systemui")
    // These AOSP selectors are hypotheses until the first pinned-image feasibility run.
    private val pinIds = setOf("com.android.settings:id/password_entry", "com.android.systemui:id/pinEntry")
    private fun find(root: AccessibilityNodeInfo, predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        val queue = java.util.ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        while (queue.isNotEmpty() && visited < 256) {
            val node = queue.removeFirst()
            visited++
            if (predicate(node)) return node
            for (index in 0 until minOf(node.childCount, 256)) {
                if (visited + queue.size >= 256) break
                node.getChild(index)?.let(queue::addLast)
            }
        }
        return null
    }

    @Synchronized private fun recordNativeResult(phase: String, code: String) {
        diagnosticPhase = phase
        diagnosticCode = code
        persistDiagnostic()
    }

    private fun persistDiagnostic() {
        // Best-effort diagnostics must never replace the original native failure.
        runCatching {
            val value = org.json.JSONObject().apply {
                put("phase", diagnosticPhase); put("native_code", diagnosticCode)
                put("root_state", diagnosticRoot); put("resource_ids", org.json.JSONArray(diagnosticIds))
                put("view_ids_reported", diagnosticViewIds)
            }
            File(context.cacheDir, "as91-prompt-ui.json").writeText(value.toString())
        }
    }

    private fun recordSystemResourceIds(phase: String) {
        // Resource IDs only: no text, credential field contents, hierarchy or screenshot.
        val ids = sortedSetOf<String>()
        val root = instrumentation.uiAutomation.rootInActiveWindow
        val rootState = when {
            root == null -> "NO_ROOT"
            root.packageName?.toString() == "com.android.settings" -> "SYSTEM_SETTINGS"
            root.packageName?.toString() == "com.android.systemui" -> "SYSTEM_UI"
            else -> "OTHER_PACKAGE"
        }
        if (root != null && root.packageName?.toString() in systemPackages) {
            find(root) {
                val id = it.viewIdResourceName
                if (id != null && id.matches(Regex("com\\.android\\.(settings|systemui):id/[A-Za-z0-9_]{1,80}")) && ids.size < 32) ids.add(id)
                false
            }
        }
        val reportIds = instrumentation.uiAutomation.serviceInfo.flags and android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS != 0
        synchronized(this) {
            diagnosticPhase = phase; diagnosticRoot = rootState
            diagnosticIds = ids.toList(); diagnosticViewIds = reportIds
            persistDiagnostic()
        }
    }

    private fun requireNativePending(phase: String) {
        try {
            unlockObservation?.requirePending(phase)
        } catch (failure: IllegalStateException) {
            // A diagnostic read failure must not mask this allowlisted Result/phase.
            runCatching { recordSystemResourceIds(phase) }
            throw failure
        }
    }

    fun awaitCredentialWindow(): AccessibilityNodeInfo {
        val deadline = SystemClock.elapsedRealtime() + 10000
        while (SystemClock.elapsedRealtime() < deadline) {
            requireNativePending("WINDOW_WAIT")
            val root = instrumentation.uiAutomation.rootInActiveWindow
            if (root != null && root.packageName?.toString() in systemPackages && find(root) { it.viewIdResourceName in pinIds || it.text?.toString() == "Разблокировать ассистента" } != null) {
                runCatching { recordSystemResourceIds("WINDOW_WAIT") }
                requireNativePending("WINDOW_WAIT")
                return root
            }
            SystemClock.sleep(100)
        }
        requireNativePending("WINDOW_TIMEOUT")
        runCatching { recordSystemResourceIds("WINDOW_TIMEOUT") }
        error("SYSTEM_CREDENTIAL_WINDOW_ABSENT")
    }

    fun enterSyntheticCredential() {
        val deadline = SystemClock.elapsedRealtime() + 35000
        awaitCredentialWindow()
        while (SystemClock.elapsedRealtime() < deadline) {
            requireNativePending("PIN_LOOKUP")
            val root = instrumentation.uiAutomation.rootInActiveWindow
            if (root == null || root.packageName?.toString() !in systemPackages) {
                SystemClock.sleep(100)
                continue
            }
            val entry = find(root) { it.viewIdResourceName in pinIds }
            if (entry != null) {
                check(entry.isVisibleToUser && entry.packageName?.toString() in systemPackages) { "PIN_ENTRY_NOT_SYSTEM" }
                requireNativePending("BEFORE_PIN")
                entry.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                requireNativePending("BEFORE_PIN")
                // Input only after observing the known foreground system credential field.
                listOf(KeyEvent.KEYCODE_8, KeyEvent.KEYCODE_6, KeyEvent.KEYCODE_4, KeyEvent.KEYCODE_2, KeyEvent.KEYCODE_0, KeyEvent.KEYCODE_9, KeyEvent.KEYCODE_ENTER).forEach(::press)
                return
            }
            val alternative = find(root) { it.isVisibleToUser && it.isClickable && it.text?.toString() in setOf("Use PIN", "Use device PIN") }
            requireNativePending("PIN_LOOKUP")
            alternative?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            SystemClock.sleep(150)
        }
        requireNativePending("PIN_TIMEOUT")
        runCatching { recordSystemResourceIds("PIN_TIMEOUT") }
        error("SYSTEM_CREDENTIAL_UI_UNRECOGNIZED")
    }

    fun press(code: Int) {
        val now = SystemClock.uptimeMillis()
        check(instrumentation.uiAutomation.injectInputEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, code, 0), true)) { "INPUT_REJECTED" }
        check(instrumentation.uiAutomation.injectInputEvent(KeyEvent(now, SystemClock.uptimeMillis(), KeyEvent.ACTION_UP, code, 0), true)) { "INPUT_REJECTED" }
    }

    fun unlock(): NativeResult {
        val before = epoch()
        val pending = beginUnlock()
        requireNativePending("BEFORE_UI")
        enterSyntheticCredential()
        val result = try {
            pending.get(10, TimeUnit.SECONDS)
        } catch (_: java.util.concurrent.TimeoutException) {
            runCatching { recordSystemResourceIds("RESULT_WAIT") }
            error("NATIVE_RESULT_WAIT_TIMEOUT")
        }
        check(result.errorCode == null) { "NATIVE_RESULT_WAIT_${NativeUnlockObservation.safeCode(result.errorCode)}" }
        val returned = (result.value as? Map<*, *>)?.get("native_epoch") as? Int ?: error("NATIVE_EPOCH_MISSING")
        assertTrue("NATIVE_EPOCH_NOT_FRESH", returned != before)
        instrumentation.runOnMainSync {
            assertTrue("GATE_NOT_OPEN", bridge.gate.foreground && bridge.gate.state == ForegroundGate.State.OPEN && bridge.gate.epoch == returned)
        }
        keys.testAuthorization()
        return result
    }

    fun requireRevokeWhileCovered() { instrumentation.runOnMainSync { assertTrue("GATE_NOT_CLOSING", bridge.gate.state == ForegroundGate.State.CLOSING); bridge.gate.requireSign("revokeSelfDevice") } }
    fun epoch(): Int { var value = 0; instrumentation.runOnMainSync { value = bridge.gate.epoch }; return value }
    fun assertLocked() { instrumentation.runOnMainSync { assertTrue("GATE_NOT_LOCKED", bridge.gate.state == ForegroundGate.State.LOCKED) } }
    fun recreate() { scenario!!.recreate(); acquireBridge() }
    fun moveTo(state: Lifecycle.State) { scenario!!.moveToState(state) }
    fun awaitForeground() {
        val deadline = SystemClock.elapsedRealtime() + 10000
        while (SystemClock.elapsedRealtime() < deadline) {
            var foreground = false
            instrumentation.runOnMainSync { foreground = bridge.gate.foreground }
            if (foreground) return
            SystemClock.sleep(100)
        }
        error("ACTIVITY_NOT_FOREGROUND")
    }
    fun bringForward() {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: error("LAUNCH_INTENT_MISSING")
        context.startActivity(intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
        instrumentation.waitForIdleSync()
        awaitForeground()
    }

    fun vaultFiles(): List<File> = listOf("session", "domain").flatMap { slot -> listOf("", ".new", ".bak").map { File(context.noBackupFilesDir, "$slot.v1.vault$it") } }
    override fun close() {
        if (!owned) return
        try { scenario?.close() } finally {
            try { vault.destroy() } finally {
                keys.destroy()
                context.getSharedPreferences("public-device-state", 0).edit().clear().commit()
            }
        }
    }

    companion object {
        private val installation = Any()
        private var installationChecked = false
        fun metric(name: String, value: String) {
            check(name in setOf("expiry_wait_ms", "ec_security_level", "aes_security_level"))
            check(value.matches(Regex("-?[0-9]{1,9}")))
            val file = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "as91-runtime-metrics.json")
            val metrics = if (file.exists()) org.json.JSONObject(file.readText()) else org.json.JSONObject()
            metrics.put(name, value.toLong())
            file.writeText(metrics.toString())
        }
    }
}

data class NativeResult(val value: Any?, val errorCode: String?)

/** JUnit/XML may retain test stacks, but never native exception messages or DTO values. */
fun nativeScenario(block: (NativeDeviceHarness) -> Unit) {
    try {
        NativeDeviceHarness().use(block)
    } catch (failure: Throwable) {
        val code = failure.message?.takeIf { it.matches(Regex("[A-Z_]{3,80}")) } ?: "NATIVE_SCENARIO_FAILED"
        throw AssertionError(code)
    }
}

/** Pure Result-order observer; contains no Android/auth actions or payload serialization. */
class NativeUnlockObservation(
    private val pending: CompletableFuture<NativeResult>,
    private val record: (String, String) -> Unit
) {
    private val phase = java.util.concurrent.atomic.AtomicReference("NATIVE_REQUEST")
    init {
        pending.whenComplete { result, failure ->
            val code = if (failure != null) "FUTURE_FAILED" else safeCode(result?.errorCode)
            record(phase.get(), code)
        }
    }
    fun requirePending(nextPhase: String) {
        require(nextPhase in phases)
        phase.set(nextPhase)
        if (!pending.isDone) return
        val result = try { pending.join() } catch (_: Exception) {
            record(nextPhase, "FUTURE_FAILED")
            error("NATIVE_${nextPhase}_FUTURE_FAILED")
        }
        val code = safeCode(result.errorCode)
        record(nextPhase, code)
        error("NATIVE_${nextPhase}_${if (result.errorCode == null) "EARLY_SUCCESS" else code}")
    }
    companion object {
        private val phases = setOf("NATIVE_REQUEST", "BEFORE_UI", "WINDOW_WAIT", "PIN_LOOKUP", "BEFORE_PIN", "WINDOW_TIMEOUT", "PIN_TIMEOUT", "RESULT_WAIT")
        fun safeCode(code: String?): String = when (code) {
            null -> "SUCCESS"
            "SECURITY_BOUNDARY", "AUTH_CANCELLED", "AUTH_UNAVAILABLE", "NOT_IMPLEMENTED" -> code
            else -> "OTHER_ERROR"
        }
    }
}
