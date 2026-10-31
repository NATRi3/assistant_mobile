package io.github.natri3.assistant.platform
import org.junit.Test
import org.junit.Assert.*
class ForegroundGateTest {
 @Test fun lifecycleAndLogoutDeadlinesFenceEveryOperation(){
 var now=100L;val gate=ForegroundGate{now};assertTrue(runCatching{gate.requireOpen()}.isFailure)
 gate.resume();val epoch=gate.authenticate();gate.requireOpen(epoch);gate.pause();assertTrue(runCatching{gate.requireOpen(epoch)}.isFailure)
 gate.resume();gate.authenticate();gate.cover();gate.requireSign("revokeSelfDevice");assertTrue(runCatching{gate.requireSign("getSelfDevice")}.isFailure);assertTrue(runCatching{gate.requireOpen()}.isFailure)
 now+=5000;assertTrue(runCatching{gate.requireSign("revokeSelfDevice")}.isFailure);gate.destroy();assertTrue(runCatching{gate.requireSign("revokeSelfDevice")}.isFailure)
 }
 @Test fun authWindowExpiresAndLockedLogoutCannotSign(){var now=0L;val gate=ForegroundGate{now};gate.resume();gate.authenticate();now=300000;assertTrue(runCatching{gate.requireOpen()}.isFailure);gate.cover();assertTrue(runCatching{gate.requireSign("revokeSelfDevice")}.isFailure)}
 @Test fun allowlistRejectsForeignOriginPathAndIds(){assertTrue(runCatching{OperationRoutes.resolve("getTask","https://foreign.invalid","https://mobile.example.invalid")}.isFailure);assertTrue(runCatching{OperationRoutes.resolve("invented",null,"https://mobile.example.invalid")}.isFailure);assertTrue(runCatching{OperationRoutes.resolve("getSelfDevice",null,"http://mobile.example.invalid")}.isFailure)}
}
