rule RAT_Generic_Indicators
{
    meta:
        description = "Indicadores genericos de Remote Access Trojans"
        severity = "high"
        author = "RAT Analyzer"
        tags = "rat", "injection", "keylog"

    strings:
        $s1 = "CreateRemoteThread" ascii
        $s2 = "VirtualAllocEx" ascii
        $s3 = "WriteProcessMemory" ascii
        $s4 = "NtCreateThreadEx" ascii
        $s5 = "RtlCreateUserThread" ascii
        $s6 = "OpenProcess" ascii
        $s7 = "CreateToolhelp32Snapshot" ascii
        $s8 = "Process32First" ascii
        $s9 = "GetAsyncKeyState" ascii
        $s10 = "SetClipboardData" ascii
        $s11 = "SetWindowsHookEx" ascii
        $s12 = "QueueUserAPC" ascii
        $s13 = "InternetOpen" ascii
        $s14 = "HttpOpenRequest" ascii
        $s15 = "WSAStartup" ascii
        $s16 = "socket" ascii
        $s17 = "connect" ascii

    condition:
        4 of them
}
