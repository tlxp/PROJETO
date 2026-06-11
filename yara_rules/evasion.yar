import "pe"

rule Evasion_Techniques
{
    meta:
        description = "Anti-debug correlacionado com deteção de VM ou ferramentas de análise"
        severity = "medium"
        author = "RAT Analyzer"
        tags = "evasion anti-debug anti-vm"
        false_positive_risk = "low"
        date = "2026-06-11"
        version = "2"

    strings:
        $dbg1 = "IsDebuggerPresent" ascii
        $dbg2 = "CheckRemoteDebuggerPresent" ascii
        $dbg3 = "NtQueryInformationProcess" ascii
        $dbg4 = "OutputDebugString" ascii
        $vm1 = "VMwareVMware" ascii
        $vm2 = "VBoxGuest" ascii
        $vm3 = "vmtoolsd.exe" ascii nocase
        $vm4 = "qemu-ga" ascii nocase
        $ana1 = "x64dbg.exe" ascii nocase
        $ana2 = "ollydbg.exe" ascii nocase
        $ana3 = "wireshark.exe" ascii nocase
        $ana4 = "procmon.exe" ascii nocase
        $sleep_obf = "Sleep" ascii

    condition:
        uint16(0) == 0x5A4D and
        filesize < 20MB and
        pe.is_pe and
        (3 of ($dbg*)) and
        (2 of ($vm*, $ana*)) and
        #sleep_obf > 3
}
