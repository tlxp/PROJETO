import "pe"

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
        $chrome_login = "Chrome\\User Data\\Default\\Login Data" ascii
        $chrome_cookies = "Chrome\\User Data\\Default\\Network\\Cookies" ascii
        $edge_login = "Edge\\User Data\\Default\\Login Data" ascii
        $firefox_profiles = "Mozilla\\Firefox\\Profiles" ascii
        $crypt1 = "CryptUnprotectData" ascii
        $crypt2 = "sqlite3_open" ascii
        $key1 = "GetAsyncKeyState" ascii
        $key2 = "SetWindowsHookExA" ascii
        $key3 = "SetWindowsHookExW" ascii
        $stealer1 = "Login Data" ascii
        $stealer2 = "Web Data" ascii

    condition:
        uint16(0) == 0x5A4D and
        filesize < 20MB and
        pe.is_pe and
        (2 of ($chrome_login, $chrome_cookies, $edge_login, $firefox_profiles)) and
        (
            (1 of ($crypt1, $crypt2) and 1 of ($stealer1, $stealer2)) or
            (2 of ($key1, $key2, $key3))
        )
}
