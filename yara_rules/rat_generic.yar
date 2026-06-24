// --- Regras genéricas de RAT (injeção, rede, persistência) ---
import "pe"

// --- RAT_Generic_Indicators ---
rule RAT_Generic_Indicators
{
    meta:
        description = "Injeção de processo + rede + (keylog ou persistência) em PE"
        severity = "high"
        author = "RAT Analyzer"
        tags = "rat injection network persistence"
        false_positive_risk = "low"
        date = "2026-06-11"
        version = "2"

    strings:
        // *Núcleo de injeção em processo remoto*
        $inj_core1 = "VirtualAllocEx" ascii
        $inj_core2 = "WriteProcessMemory" ascii
        // *Técnicas alternativas de execução remota*
        $inj_extra1 = "CreateRemoteThread" ascii
        $inj_extra2 = "NtCreateThreadEx" ascii
        $inj_extra3 = "QueueUserAPC" ascii
        // *APIs de comunicação de rede*
        $net1 = "InternetConnect" ascii
        $net2 = "HttpSendRequest" ascii
        $net3 = "WSASocket" ascii
        $net4 = "connect" ascii
        // *Captura de teclas e hooks de teclado*
        $key1 = "GetAsyncKeyState" ascii
        $key2 = "SetWindowsHookExA" ascii
        $key3 = "SetWindowsHookExW" ascii
        // *Persistência via registo Run e escrita de valores*
        $pers1 = "Software\\Microsoft\\Windows\\CurrentVersion\\Run" ascii wide
        $pers2 = "RegSetValueEx" ascii

    condition:
        // *Apenas ficheiros PE Windows abaixo de 20 MB*
        uint16(0) == 0x5A4D and
        filesize < 20MB and
        pe.is_pe and
        // *PE com mais de 2 secções (não trivial)*
        pe.number_of_sections > 2 and
        // *Ambas as APIs de injeção obrigatórias*
        all of ($inj_core*) and
        // *Pelo menos uma técnica extra de execução remota*
        (1 of ($inj_extra*)) and
        // *Pelo menos 2 APIs de rede*
        (2 of ($net*)) and
        // *Keylog ou persistência no registo*
        (1 of ($key*, $pers*))
}
