/*
 * ANTIVIRUS TEST SAMPLE ONLY - EDUCATIONAL USE
 * Simulates patterns that RAT/malware analyzers flag. Does NOT perform harmful actions.
 * Use only on your own machine to test your antivirus/analyzer.
 */
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

class Program
{
    #region Simulated C2 / Config (strings only)

    private static readonly string[] C2Urls = {
        "http://192.168.1.100:4444/beacon",
        "https://c2.evil-domain.test/api/collect",
        "tcp://10.0.0.1:31337",
        "https://pastebin.com/raw/xxxx",
        "http://10.0.0.1:8080/c2/report"
    };

    // Literais para detecção por YARA/static (nomes de API nativas)
    private static readonly string NativeApiEvasion = "IsDebuggerPresent";
    private static readonly string NativeApiEvasion2 = "CheckRemoteDebuggerPresent";
    private static readonly string NativeApiInjection = "NtCreateThreadEx";
    private static readonly string NativeApiInjection2 = "RtlCreateUserThread";
    private static readonly string NativeApiProcess = "CreateToolhelp32Snapshot";
    private static readonly string NativeApiProcess2 = "Process32First";
    private static readonly string NativeApiProcess3 = "OpenProcess";
    private static readonly string NativeApiKeylog = "SetWindowsHookEx";
    private static readonly string NativeApiClipboard = "SetClipboardData";
    private static readonly string NativeApiMemory = "VirtualProtect";
    private static readonly string NativeApiMemory2 = "NtProtectVirtualMemory";

    private static string GetPayloadHost() =>
        "192" + ".168." + "1." + (1).ToString();

    private static string GetShellPath() =>
        Environment.GetFolderPath(Environment.SpecialFolder.System) +
        Path.DirectorySeparatorChar + "c" + "md" + ".e" + "xe";

    private static string XorDecode(byte[] data, byte key)
    {
        var result = new byte[data.Length];
        for (int i = 0; i < data.Length; i++) result[i] = (byte)(data[i] ^ key);
        return Encoding.UTF8.GetString(result);
    }

    #endregion

    #region Anti-analysis (simulated checks only)

    private static bool SimulatedAntiDebug()
    {
        if (Debugger.IsAttached)
        {
            Console.WriteLine("[TEST] Debugger detected - would exit in real sample.");
            return true;
        }
        return false;
    }

    private static void SimulatedAntiVmStrings()
    {
        string[] vmArtifacts = {
            "VBOX", "VMware", "vmtoolsd", "VBoxService", "vmware-vmx",
            "sandbox", "wireshark", "procmon", "x64dbg", "ollydbg", "idaq"
        };
        string env = Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER") ?? "";
        foreach (var a in vmArtifacts)
            if (env.IndexOf(a, StringComparison.OrdinalIgnoreCase) >= 0)
                Console.WriteLine("[TEST] VM/analysis artifact string used in check: " + a);
        _ = NativeApiEvasion; _ = NativeApiEvasion2;
    }

    private static void SimulatedTimingCheck()
    {
        var sw = Stopwatch.StartNew();
        Thread.Sleep(12);
        sw.Stop();
        if (sw.ElapsedMilliseconds < 5)  // too fast = likely stepped in debugger
            Console.WriteLine("[TEST] Timing anomaly (would branch in real sample).");
    }

    #endregion

    #region Persistence / Registry (read-only paths)

    private static void SimulatedPersistenceStrings()
    {
        string runKey = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run";
        string runOnce = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\RunOnce";
        string winlogon = "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon";
        string valueName = "Updater";
        string shellValue = "Shell";
        try
        {
            using (var key = Registry.CurrentUser.OpenSubKey(runKey, writable: false))
            {
                if (key != null)
                    _ = key.GetValueNames();  // read only, no write
            }
        }
        catch { /* ignore */ }
    }

    #endregion

    #region Credential / Stealer paths (strings + safe file read)

    private static void SimulatedStealerPaths()
    {
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string[] paths = {
            Path.Combine(localAppData, "Google\\Chrome\\User Data\\Default\\Login Data"),
            Path.Combine(localAppData, "Microsoft\\Edge\\User Data\\Default\\Login Data"),
            Path.Combine(appData, "Mozilla\\Firefox\\Profiles"),
            Path.Combine(localAppData, "Discord"),
            Path.Combine(appData, "Telegram Desktop"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "passwords.txt")
        };
        foreach (var p in paths)
            _ = p;  // only reference, no access to real files
    }

    private static void SimulatedKeylogScreenshotStrings()
    {
        string keylogBuffer = "keylog_buffer";
        string screenshotDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "screens");
        string hookProc = "GetAsyncKeyState";
        string setHook = "SetWindowsHookEx";
        string getForeground = "GetForegroundWindow";
        string loginData = "Login Data";  // stealer path pattern
        string cookies = "Cookies";
        _ = keylogBuffer; _ = screenshotDir; _ = hookProc; _ = setHook; _ = getForeground;
        _ = loginData; _ = cookies; _ = NativeApiKeylog; _ = NativeApiClipboard;
    }

    #endregion

    #region Injection / Process (API names as strings only)

    private static void SimulatedInjectionStrings()
    {
        string[] apis = {
            "VirtualAllocEx", "WriteProcessMemory", "CreateRemoteThread",
            "NtCreateThreadEx", "RtlCreateUserThread", "QueueUserAPC",
            "kernel32.dll", "ntdll.dll", "OpenProcess", "CreateToolhelp32Snapshot",
            "Process32First", "Process32Next", "EnumProcesses"
        };
        foreach (var api in apis)
            _ = api;
        _ = NativeApiInjection; _ = NativeApiInjection2;
        _ = NativeApiProcess; _ = NativeApiProcess2; _ = NativeApiProcess3;
        _ = NativeApiMemory; _ = NativeApiMemory2;
    }

    #endregion

    #region Payload / Dropper (encoded strings only)

    private static void SimulatedEncodedPayloads()
    {
        string b64Payload = "aHR0cDovL2V4YW1wbGUuY29tL2JhZA==";
        string decoded = Encoding.UTF8.GetString(Convert.FromBase64String(b64Payload));

        byte[] xorPayload = { 0x2B, 0x2E, 0x2E, 0x33, 0x28, 0x2E, 0x26, 0x21 };  // "example" XOR 0x4B
        string xorDecoded = XorDecode(xorPayload, 0x4B);

        _ = decoded; _ = xorDecoded;
    }

    #endregion

    #region Network (safe request only)

    private static async Task SimulatedC2CallbackAsync()
    {
        using var client = new HttpClient();
        client.Timeout = TimeSpan.FromSeconds(5);
        client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Agent/1.0");
        try
        {
            var response = await client.GetAsync("http://example.com");
            string content = await response.Content.ReadAsStringAsync();
            Console.WriteLine("[TEST] Request length: " + content.Length);
        }
        catch (Exception ex)
        {
            Console.WriteLine("[TEST] Network: " + ex.Message);
        }
    }

    #endregion

    #region Crypto (simulated key / AES names)

    private static void SimulatedCryptoStrings()
    {
        string aesKey = "AES.Key.256.bits.placeholder.for.test";
        string iv = "1234567890123456";
        _ = aesKey; _ = iv;
        try
        {
            using (var aes = Aes.Create())
            {
                aes.KeySize = 256;
                _ = aes.Key; _ = aes.IV;  // only reference, no encrypt
            }
        }
        catch { /* ignore */ }
    }

    #endregion

    #region Mutex / Single instance (name only)

    private static void SimulatedMutexName()
    {
        string mutexName = "Global\\" + "SINGLE_INSTANCE_" + Guid.NewGuid().ToString("N").Substring(0, 8);
        _ = mutexName;
    }

    #endregion

    #region Report (harmless file write)

    private static string WriteReport(string[] collected)
    {
        string reportPath = Path.Combine(Path.GetTempPath(), "av_test_report_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".txt");
        var sb = new StringBuilder();
        sb.AppendLine("[ANTIVIRUS TEST] Simulated patterns - no harmful action performed.");
        sb.AppendLine("Generated: " + DateTime.UtcNow.ToString("o"));
        sb.AppendLine();
        sb.AppendLine("--- Simulated exfil paths / strings ---");
        foreach (var line in collected)
            sb.AppendLine(line);
        File.WriteAllText(reportPath, sb.ToString());
        return reportPath;
    }

    #endregion

    static async Task Main(string[] args)
    {
        var collected = new List<string>();

        SimulatedAntiDebug();
        SimulatedAntiVmStrings();
        SimulatedTimingCheck();

        SimulatedPersistenceStrings();
        collected.Add("Run key (path only): SOFTWARE\\...\\Run");

        SimulatedStealerPaths();
        SimulatedKeylogScreenshotStrings();
        collected.Add("Keylog/screenshot dir (string): keylog_buffer, screens");

        SimulatedInjectionStrings();
        collected.Add("Injection APIs (names only): VirtualAllocEx, CreateRemoteThread, ...");

        SimulatedEncodedPayloads();
        collected.Add("Base64/XOR decoded URL (example.com)");

        await SimulatedC2CallbackAsync();
        collected.Add("C2 callback: GET example.com (safe)");

        SimulatedCryptoStrings();
        collected.Add("AES/crypto references");

        SimulatedMutexName();
        collected.Add("Single-instance mutex name (not created)");

        collected.Add("Shell path (concat): " + GetShellPath());
        collected.Add("Payload host: " + GetPayloadHost());

        // Garantir que C2 URLs aparecem no binário (para análise estática/YARA)
        foreach (var url in C2Urls)
            collected.Add("C2 URL: " + url);

        string reportPath = WriteReport(collected.ToArray());
        Console.WriteLine("[TEST] Advanced sample finished. Report: " + reportPath);
    }
}
