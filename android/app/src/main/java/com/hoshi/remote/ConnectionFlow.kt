package com.hoshi.remote

import java.net.URI

/** The native screen selected before the remote WebView is allowed to appear. */
internal sealed interface EntryStep {
    data object Setup : EntryStep
    data class Probe(val candidates: List<String>) : EntryStep
}

internal object ConnectionFlow {
    fun candidates(current: String, known: List<String>): List<String> =
        (listOf(current) + known).filter { it.isNotBlank() }.distinct()

    fun initial(current: String, known: List<String>): EntryStep =
        candidates(current, known).let { if (it.isEmpty()) EntryStep.Setup else EntryStep.Probe(it) }

    fun resolve(candidates: List<String>, reachable: (String) -> Boolean): String? =
        candidates.firstOrNull(reachable)

    data class ProbeCheck(val host: String, val failure: String?)
    data class ProbeReport(val found: String?, val checked: List<ProbeCheck>)

    fun probe(candidates: List<String>, check: (String) -> String?): ProbeReport {
        val checked = mutableListOf<ProbeCheck>()
        for (host in candidates) {
            val failure = check(host)
            checked.add(ProbeCheck(host, failure))
            if (failure == null) return ProbeReport(host, checked)
        }
        return ProbeReport(null, checked)
    }

    data class ManualAttempt(val candidates: List<String>, val replaceComputer: Boolean)

    fun manualAttempt(input: String, current: String, known: List<String>): ManualAttempt {
        val sameComputer = input == current || input in known
        return ManualAttempt(if (sameComputer) candidates(input, listOf(current) + known) else listOf(input), !sameComputer)
    }

    data class PairingLink(val hosts: List<String>, val code: String)

    /** The PC's single QR contains one browser URL and every usable fallback IP. */
    fun pairingLink(text: String): PairingLink? {
        val uri = runCatching { URI(text.trim()) }.getOrNull() ?: return null
        if (uri.scheme != "http" || uri.port != Prefs.HTTP_PORT || uri.path !in listOf("", "/")) return null
        val primary = uri.host?.takeIf(::privateIpv4) ?: return null
        val fields = uri.fragment?.split('&')?.mapNotNull {
            val parts = it.split('=', limit = 2)
            if (parts.size == 2) parts[0] to parts[1] else null
        }?.toMap() ?: return null
        val code = fields["pair"]?.takeIf { it.matches(Regex("[0-9]{6}")) } ?: return null
        val alts = fields["alt"].orEmpty().split(',').filter(::privateIpv4)
        return PairingLink((listOf(primary) + alts).distinct().take(6), code)
    }

    private fun privateIpv4(host: String): Boolean {
        val parts = host.split('.').map { it.toIntOrNull() ?: return false }
        if (parts.size != 4 || parts.any { it !in 0..255 }) return false
        return parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 172 && parts[1] in 16..31)
    }
}
