import "pe"

rule C2_Communication_Patterns
{
    meta:
        description = "Beacon/exfil C&C com TLD suspeito, webhook ou IP:porta + path de beacon"
        severity = "high"
        author = "RAT Analyzer"
        tags = "c2 beacon exfil webhook"
        false_positive_risk = "low"
        date = "2026-06-11"
        version = "2"

    strings:
        $suspicious_tld = /https?:\/\/[a-zA-Z0-9.-]+\.(onion|bit|tk|ml|ga|cf|gq)\//
        $discord_webhook = "discord.com/api/webhooks/" ascii nocase
        $discord_webhook_alt = "discordapp.com/api/webhooks/" ascii nocase
        $telegram_api = "api.telegram.org/bot" ascii nocase
        $beacon_path = "/beacon" ascii nocase
        $collect_path = "/api/collect" ascii nocase
        $gate_path = "/gate.php" ascii nocase
        $ip_port = /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{2,5}/
        $post_host = "Host:" ascii
        $post_verb = "POST " ascii

    condition:
        uint16(0) == 0x5A4D and
        filesize < 20MB and
        pe.is_pe and
        (
            ($suspicious_tld and (1 of ($beacon_path, $collect_path, $gate_path))) or
            (1 of ($discord_webhook, $discord_webhook_alt, $telegram_api)) or
            ($ip_port and (1 of ($beacon_path, $collect_path, $gate_path)) and $post_verb and $post_host)
        )
}
