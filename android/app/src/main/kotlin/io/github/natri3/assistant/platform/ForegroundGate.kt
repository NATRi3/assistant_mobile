package io.github.natri3.assistant.platform
class ForegroundGate(private val now:()->Long) {
 enum class State { LOCKED, OPEN, CLOSING, DESTROYED }
 var state=State.LOCKED; private set
 var epoch=1; private set
 var foreground=false; private set
 private var authenticatedAt=-1L
 private var closingDeadline=-1L
 fun resume(){foreground=true}
 fun pause(){foreground=false;lock()}
 fun lock(){epoch++;state=State.LOCKED;authenticatedAt=-1}
 fun authenticate():Int {check(foreground && state!=State.CLOSING);epoch++;authenticatedAt=now();state=State.OPEN;return epoch}
 fun requireOpen(expected:Int?=null){check(foreground&&state==State.OPEN&&authenticatedAt>=0&&now()-authenticatedAt in 0 until 300000 && (expected==null||epoch==expected)){"LOCKED"}}
 fun cover(){val allowed=runCatching{requireOpen()}.isSuccess;epoch++;state=State.CLOSING;closingDeadline=if(allowed)now()+5000 else -1}
 fun requireSign(operation:String){if(state==State.CLOSING){check(operation=="revokeSelfDevice"&&foreground&&now()<closingDeadline&&now()-authenticatedAt in 0 until 300000){"LOCKED"}}else requireOpen()}
 fun destroy(){epoch++;state=State.DESTROYED;authenticatedAt=-1;closingDeadline=-1}
}
