// --- Módulo: gemini.ts ---
// *Integração com API Gemini para assistência na análise de pseudo-C*

// *Máximo de caracteres do excerto de código C enviado ao modelo*
export const GEMINI_CODE_CHAR_LIMIT = 16_000;

// *Máximo de caracteres da pergunta do utilizador*
export const GEMINI_USER_MESSAGE_CHAR_LIMIT = 1_000;

export const GEMINI_MODEL = "gemini-2.0-flash";

export type GeminiChatMessage = {
  role: "user" | "assistant";
  text: string;
};

export type CodeExcerpt = {
  text: string;
  lineInfo: string;
  truncated: boolean;
};

// --- Constrói excerto de código para enviar ao modelo ---
export function buildCodeExcerpt(
  lines: string[],
  options: {
    displayLineRanges?: { start: number; end: number }[] | null;
    windowStart?: number | null;
    windowEnd?: number | null;
    maxInitialLines?: number;
    showAll?: boolean;
    charLimit?: number;
  },
): CodeExcerpt {
  const charLimit = options.charLimit ?? GEMINI_CODE_CHAR_LIMIT;
  const chunks: { start: number; end: number; text: string }[] = [];

  if (options.displayLineRanges?.length) {
    for (const range of options.displayLineRanges) {
      const start = Math.max(1, Math.floor(range.start));
      const end = Math.max(start, Math.floor(range.end));
      const text = lines.slice(start - 1, end).join("\n");
      if (text.trim()) chunks.push({ start, end, text });
    }
  } else if (
    options.windowStart != null &&
    options.windowEnd != null &&
    options.windowStart >= 1
  ) {
    const start = options.windowStart;
    const end = options.windowEnd;
    chunks.push({ start, end, text: lines.slice(start - 1, end).join("\n") });
  } else {
    const limit = options.showAll ? lines.length : Math.min(lines.length, options.maxInitialLines ?? lines.length);
    if (limit > 0) {
      chunks.push({ start: 1, end: limit, text: lines.slice(0, limit).join("\n") });
    }
  }

  const fullText = chunks.map((c) => c.text).join("\n\n");
  const lineInfo =
    chunks.length === 0
      ? "sem linhas"
      : chunks.length === 1
        ? `linhas ${chunks[0].start}–${chunks[0].end}`
        : `${chunks.length} blocos (${chunks.map((c) => `${c.start}–${c.end}`).join(", ")})`;

  if (fullText.length <= charLimit) {
    return { text: fullText, lineInfo, truncated: false };
  }

  return {
    text: `${fullText.slice(0, charLimit)}\n\n/* … excerto truncado (${fullText.length.toLocaleString()} caracteres no total) … */`,
    lineInfo,
    truncated: true,
  };
}

type GeminiGenerateResponse = {
  candidates?: Array<{
    content?: { parts?: Array<{ text?: string }> };
  }>;
  error?: { message?: string };
};

// --- Envia pergunta ao Gemini com contexto de código C ---
export async function askGemini(
  apiKey: string,
  messages: GeminiChatMessage[],
  codeExcerpt: string,
): Promise<string> {
  const systemContext = [
    "És um assistente de análise de malware que explica código C descompilado.",
    "Responde em português de Portugal, de forma clara e concisa.",
    "Baseia-te apenas no excerto fornecido; se faltar contexto, indica as limitações.",
    "",
    "Excerto de código C:",
    "```c",
    codeExcerpt,
    "```",
  ].join("\n");

  const contents = [
    {
      role: "user",
      parts: [{ text: systemContext }],
    },
    {
      role: "model",
      parts: [{ text: "Compreendido. Posso explicar o excerto de código C." }],
    },
    ...messages.map((m) => ({
      role: m.role === "user" ? "user" : "model",
      parts: [{ text: m.text }],
    })),
  ];

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`;

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ contents }),
  });

  const data = (await res.json()) as GeminiGenerateResponse;

  if (!res.ok) {
    const msg = data.error?.message ?? `Erro HTTP ${res.status}`;
    throw new Error(msg);
  }

  const text = data.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("")?.trim();
  if (!text) throw new Error("Resposta vazia do Gemini.");
  return text;
}

const GEMINI_MOCK_DELAY_MS = 900;

// --- Resposta fixa para demonstração (sem chamada à API) ---
export function getGeminiMockReply(_question: string, lineInfo: string): string {
  return [
    "Este excerto de código C descompilado parece pertencer a um binário .NET reconstituído e apresenta vários comportamentos típicos de malware:",
    "",
    "1. **Leitura de configuração** (`read_config`) — abre `config.ini` e regista o conteúdo, possivelmente para obter parâmetros de C2 ou caminhos de ficheiros.",
    "2. **Captura de teclas** (`capture_keystrokes`) — usa `GetAsyncKeyState` para detetar combinações de teclas (ex.: Shift+Ctrl), comportamento associado a keyloggers.",
    "3. **Persistência** (`persist_registry`) — escreve em `HKCU\\...\\Run` para executar `evil.exe` no arranque do sistema.",
    "4. **Escrita suspeita** (`suspicious_function`) — cria/escreve em `log.txt` dados que podem ser exfiltrados ou usados como marcador.",
    "5. **Exfiltração / C2** (`exfil_data`, `get_c2_url`) — monta um URL por concatenação de strings (ofuscação simples) e usa WinINet (`InternetOpenUrlA`) para contactar um servidor remoto.",
    "",
    `A análise baseou-se no excerto visível (${lineInfo}). Em modo demonstração não é feita qualquer chamada à API do Gemini.`,
  ].join("\n");
}

// --- Simula latência de rede no modo demo ---
export function askGeminiMock(question: string, lineInfo: string): Promise<string> {
  return new Promise((resolve) => {
    window.setTimeout(() => resolve(getGeminiMockReply(question, lineInfo)), GEMINI_MOCK_DELAY_MS);
  });
}
