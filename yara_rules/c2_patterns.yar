// --- Regra: c2_patterns ---
// --- Padrões C2 (beacon, exfiltração, webhooks) ---
import "pe"

// --- Regra: C2_Communication_Patterns ---
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
        // URLs com TLDs frequentemente abusados
        $suspicious_tld = /https?:\/\/[a-zA-Z0-9.-]+\.(onion|bit|tk|ml|ga|cf|gq)\//
        // Webhooks Discord — canal C2 comum
        $discord_webhook = "discord.com/api/webhooks/" ascii nocase
        $discord_webhook_alt = "discordapp.com/api/webhooks/" ascii nocase
        // API do Telegram Bot — exfiltração via chat
        $telegram_api = "api.telegram.org/bot" ascii nocase
        // Paths típicos de beacon e gateway
        $beacon_path = "/beacon" ascii nocase
        $collect_path = "/api/collect" ascii nocase
        $gate_path = "/gate.php" ascii nocase
        // Endereço IP:porta embutido em strings
        $ip_port = /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{2,5}/
        // Cabeçalhos HTTP de pedido POST
        $post_host = "Host:" ascii
        $post_verb = "POST " ascii

    condition:
        // Apenas ficheiros PE Windows abaixo de 20 MB
        uint16(0) == 0x5A4D and
        filesize < 20MB and
        pe.is_pe and
        (
            // TLD suspeito + path de beacon/collect/gate
            ($suspicious_tld and (1 of ($beacon_path, $collect_path, $gate_path))) or
            // Webhook Discord ou bot Telegram
            (1 of ($discord_webhook, $discord_webhook_alt, $telegram_api)) or
            // IP:porta + path + verbos HTTP POST com Host
            ($ip_port and (1 of ($beacon_path, $collect_path, $gate_path)) and $post_verb and $post_host)
        )
}
