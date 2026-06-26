# --- Regra: stealer ---
# --- Indicadores de stealer (credenciais de browser) ---
import "pe"

// --- Regra: Stealer_Credential_Indicators ---
rule Stealer_Credential_Indicators
{
    meta:
        description = "Paths de credenciais de browser + API de desencriptação ou hook de teclado"
        severity = "high"
        author = "RAT Analyzer"
        tags = "stealer keylog credentials browser"
        false_positive_risk = "low"
        date = "2026-06-11"
        version = "2"

    strings:
        // Paths de bases de dados de credenciais Chrome
        $chrome_login = "Chrome\\User Data\\Default\\Login Data" ascii
        $chrome_cookies = "Chrome\\User Data\\Default\\Network\\Cookies" ascii
        // Paths de credenciais Edge e Firefox
        $edge_login = "Edge\\User Data\\Default\\Login Data" ascii
        $firefox_profiles = "Mozilla\\Firefox\\Profiles" ascii
        // APIs de desencriptação DPAPI e SQLite
        $crypt1 = "CryptUnprotectData" ascii
        $crypt2 = "sqlite3_open" ascii
        // Captura de teclas via hooks
        $key1 = "GetAsyncKeyState" ascii
        $key2 = "SetWindowsHookExA" ascii
        $key3 = "SetWindowsHookExW" ascii
        // Nomes genéricos de ficheiros de credenciais
        $stealer1 = "Login Data" ascii
        $stealer2 = "Web Data" ascii

    condition:
        // Apenas ficheiros PE Windows abaixo de 20 MB
        uint16(0) == 0x5A4D and
        filesize < 20MB and
        pe.is_pe and
        // Pelo menos 2 paths de browser distintos
        (2 of ($chrome_login, $chrome_cookies, $edge_login, $firefox_profiles)) and
        (
            // Desencriptação + ficheiro de credenciais
            (1 of ($crypt1, $crypt2) and 1 of ($stealer1, $stealer2)) or
            // Ou dois indicadores de keylog
            (2 of ($key1, $key2, $key3))
        )
}
