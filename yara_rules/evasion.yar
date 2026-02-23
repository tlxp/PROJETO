rule Evasion_Techniques
{
    meta:
        description = "Tecnicas de evasao de deteccao e anti-analise"
        severity = "medium"
        author = "RAT Analyzer"
        tags = "evasion", "anti-debug", "anti-vm"

    strings:
        $s1 = "IsDebuggerPresent" ascii
        $s2 = "CheckRemoteDebuggerPresent" ascii
        $s3 = "OutputDebugString" ascii
        $s4 = "FindWindow" ascii
        $s5 = "VirtualProtect" ascii
        $s6 = "NtProtectVirtualMemory" ascii
        $s7 = "VBOX" ascii
        $s8 = "VMware" ascii
        $s9 = "vmtoolsd" ascii
        $s10 = "x64dbg" ascii
        $s11 = "ollydbg" ascii
        $s12 = "idaq" ascii
        $s13 = "procmon" ascii
        $s14 = "wireshark" ascii
        $s15 = "sandbox" ascii

    condition:
        3 of them
}
