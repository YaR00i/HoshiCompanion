package com.hoshi.remote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ConnectionFlowTest {
    @Test
    fun savedAddressDoesNotOpenBlankWebViewBeforeConnectionCheck() {
        assertEquals(
            EntryStep.Probe(listOf("10.8.1.2", "192.168.0.94")),
            ConnectionFlow.initial("10.8.1.2", listOf("192.168.0.94")),
        )
    }

    @Test
    fun unreachableVpnFallsBackToKnownHomeAddress() {
        val tried = mutableListOf<String>()
        val found = ConnectionFlow.resolve(listOf("10.8.1.2", "192.168.0.94")) {
            tried.add(it)
            it == "192.168.0.94"
        }
        assertEquals("192.168.0.94", found)
        assertEquals(listOf("10.8.1.2", "192.168.0.94"), tried)
        assertEquals(
            ConnectionFlow.ProbeReport("192.168.0.94", listOf(
                ConnectionFlow.ProbeCheck("10.8.1.2", "истекло время ожидания"),
                ConnectionFlow.ProbeCheck("192.168.0.94", null))),
            ConnectionFlow.probe(listOf("10.8.1.2", "192.168.0.94")) {
                if (it == "192.168.0.94") null else "истекло время ожидания"
            },
        )
    }

    @Test
    fun allUnreachableAddressesStayOnNativeRecoveryScreen() {
        assertNull(ConnectionFlow.resolve(listOf("10.8.1.2", "192.168.0.94")) { false })
        assertEquals(
            ConnectionFlow.ProbeReport(null, listOf(
                ConnectionFlow.ProbeCheck("10.8.1.2", "нет маршрута"),
                ConnectionFlow.ProbeCheck("192.168.0.94", "нет маршрута"))),
            ConnectionFlow.probe(listOf("10.8.1.2", "192.168.0.94")) { "нет маршрута" },
        )
    }

    @Test
    fun badManualAddressDoesNotDiscardTheSavedComputer() {
        assertEquals(
            ConnectionFlow.ManualAttempt(listOf("192.168.0.95"), true),
            ConnectionFlow.manualAttempt("192.168.0.95", "10.8.1.2", listOf("10.8.1.2", "192.168.0.94")),
        )
        assertEquals(
            ConnectionFlow.ManualAttempt(listOf("192.168.0.94", "10.8.1.2"), false),
            ConnectionFlow.manualAttempt("192.168.0.94", "10.8.1.2", listOf("10.8.1.2", "192.168.0.94")),
        )
    }

    @Test
    fun qrKeepsPairingCodeAndAllUsableAddresses() {
        assertEquals(
            ConnectionFlow.PairingLink(listOf("10.8.1.2", "192.168.0.94", "172.22.1.5"), "123456"),
            ConnectionFlow.pairingLink("http://10.8.1.2:18770/#pair=123456&alt=192.168.0.94,172.22.1.5,26.1.2.3"),
        )
        assertNull(ConnectionFlow.pairingLink("http://example.com:18770/#pair=123456"))
    }
}
