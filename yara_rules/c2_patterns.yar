rule C2_Communication_Patterns
{
    meta:
        description = "Padroes de comunicacao C&C e exfiltracao"
        severity = "high"
        author = "RAT Analyzer"
        tags = "c2", "beacon", "exfil"

    strings:
        $s1 = /http[s]?:\/\/[a-zA-Z0-9.-]+\.(onion|bit|tk|ml|ga|cf|gq)/
        $s2 = /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{2,5}/
        $s3 = "POST /" ascii
        $s4 = "GET /" ascii
        $s5 = "User-Agent:" ascii
        $s6 = "/beacon" ascii
        $s7 = "/api/collect" ascii
        $s8 = "pastebin.com" ascii
        $s9 = "tcp://" ascii
        $s10 = "c2." ascii

    condition:
        2 of them
}
