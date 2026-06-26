// --- Regra: evasion ---
// --- Técnicas de evasão (anti-debug, anti-VM) ---
import "pe"

// --- Regra: Evasion_Techniques ---
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
        // APIs de depuração remota e local
        $dbg1 = "IsDebuggerPresent" ascii
        $dbg2 = "CheckRemoteDebuggerPresent" ascii
        $dbg3 = "NtQueryInformationProcess" ascii
        $dbg4 = "OutputDebugString" ascii
        // Marcadores de hipervisor e agentes de VM
        $vm1 = "VMwareVMware" ascii
        $vm2 = "VBoxGuest" ascii
        $vm3 = "vmtoolsd.exe" ascii nocase
        $vm4 = "qemu-ga" ascii nocase
        // Processos típicos de ferramentas de análise
        $ana1 = "x64dbg.exe" ascii nocase
        $ana2 = "ollydbg.exe" ascii nocase
        $ana3 = "wireshark.exe" ascii nocase
        $ana4 = "procmon.exe" ascii nocase
        // Sleep repetido — possível ofuscação de timing
        $sleep_obf = "Sleep" ascii

    condition:
        // Apenas ficheiros PE Windows abaixo de 20 MB
        uint16(0) == 0x5A4D and
        filesize < 20MB and
        pe.is_pe and
        // Pelo menos 3 indicadores de anti-debug
        (3 of ($dbg*)) and
        // Pelo menos 2 indicadores de VM ou ferramenta de análise
        (2 of ($vm*, $ana*)) and
        // Sleep referenciado mais de 3 vezes
        #sleep_obf > 3
}
