rule Stealer_Credential_Indicators
{
    meta:
        description = "Indicadores de credential stealers e keyloggers"
        severity = "high"
        author = "RAT Analyzer"
        tags = "stealer keylog credentials browser"

    strings:
        $s1 = "Login Data" ascii
        $s2 = "Cookies" ascii
        $s3 = "keylog_buffer" ascii
        $s4 = "User Data" ascii
        $s5 = "GetAsyncKeyState" ascii
        $s6 = "SetWindowsHookEx" ascii
        $s7 = "Chrome\\User Data" ascii
        $s8 = "Edge\\User Data" ascii
        $s9 = "Firefox\\Profiles" ascii
        $s10 = "Discord" ascii
        $s11 = "Telegram Desktop" ascii
        $s12 = "passwords.txt" ascii
        $s13 = "screens" ascii

    condition:
        3 of them
}
