package io.github.natri3.assistant.platform
import org.junit.Test
import org.junit.Assert.*
class DomainReadTicketsTest {
    @Test fun oneUseSupersedeOriginalDeadlineAndClock(){
        var now=ClockSample(1,3,100,104)
        val tickets=DomainReadTickets(object:DomainClock{override fun sample()=now})
        val a=tickets.begin(7,"getSelfDevice",null,null,0,"owned")
        val b=tickets.begin(7,"getSelfDevice",null,null,0,"owned")
        assertTrue(runCatching{tickets.requireTicket(a.id,7,"owned")}.isFailure)
        assertEquals(b,tickets.requireTicket(b.id,7,"owned"))
        now=now.copy(elapsed=5001)
        assertTrue(runCatching{tickets.requireTicket(b.id,7,"owned")}.isFailure)
        now=now.copy(elapsed=8)
        val c=tickets.begin(7,"getSelfDevice",null,null,0,"owned")
        tickets.consume(c)
        assertTrue(runCatching{tickets.requireTicket(c.id,7,"owned")}.isFailure)
        val d=tickets.begin(7,"getSelfDevice",null,null,0,"owned")
        now=now.copy(lower=200,upper=204)
        assertTrue(runCatching{tickets.requireTicket(d.id,7,"owned")}.isFailure)
    }
}
