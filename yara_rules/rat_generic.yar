import "pe"

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
        $inj_core1 = "VirtualAllocEx" ascii
        $inj_core2 = "WriteProcessMemory" ascii
        $inj_extra1 = "CreateRemoteThread" ascii
        $inj_extra2 = "NtCreateThreadEx" ascii
        $inj_extra3 = "QueueUserAPC" ascii
        $net1 = "InternetConnect" ascii
        $net2 = "HttpSendRequest" ascii
        $net3 = "WSASocket" ascii
        $net4 = "connect" ascii
        $key1 = "GetAsyncKeyState" ascii
        $key2 = "SetWindowsHookExA" ascii
        $key3 = "SetWindowsHookExW" ascii
        $pers1 = "Software\\Microsoft\\Windows\\CurrentVersion\\Run" ascii wide
        $pers2 = "RegSetValueEx" ascii

    condition:
        uint16(0) == 0x5A4D and
        filesize < 20MB and
        pe.is_pe and
        pe.number_of_sections > 2 and
        all of ($inj_core*) and
        (1 of ($inj_extra*)) and
        (2 of ($net*)) and
        (1 of ($key*, $pers*))
}
