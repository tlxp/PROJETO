// --- Módulo: GeminiAssistDialog.tsx ---
// Diálogo de assistência Gemini para excerto de código C.

import React, { useCallback, useEffect, useRef, useState } from "react";
import { Loader2, Send, Trash2 } from "lucide-react";
import GeminiIcon from "@/components/GeminiIcon";
import {
  askGemini,
  askGeminiMock,
  GEMINI_USER_MESSAGE_CHAR_LIMIT,
  type CodeExcerpt,
  type GeminiChatMessage,
} from "@/lib/gemini";
import { clearGeminiApiKey, getGeminiApiKey, setGeminiApiKey } from "@/lib/geminiApiKey";

type GeminiAssistDialogProps = {
  open: boolean;
  onClose: () => void;
  codeExcerpt: CodeExcerpt;
  // *Respostas simuladas — apenas no layout mock*
  allowMock?: boolean;
};

const DEFAULT_QUESTION = "O que faz este excerto de código C?";

const GeminiMockToggle: React.FC<{
  checked: boolean;
  onChange: (checked: boolean) => void;
  id: string;
}> = ({ checked, onChange, id }) => (
  <label htmlFor={id} className="flex cursor-pointer items-center gap-2.5 select-none">
    <button
      id={id}
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`relative h-5 w-9 shrink-0 rounded-full transition-colors ${
        checked ? "bg-primary" : "bg-muted-foreground/30"
      }`}
    >
      <span
        className={`absolute top-0.5 left-0.5 h-4 w-4 rounded-full bg-background shadow transition-transform ${
          checked ? "translate-x-4" : "translate-x-0"
        }`}
      />
    </button>
    <span className="text-[12px] text-foreground">Modo demonstração (sem API key)</span>
  </label>
);

// --- Componente ---
const GeminiAssistDialog: React.FC<GeminiAssistDialogProps> = ({
  open,
  onClose,
  codeExcerpt,
  allowMock = false,
}) => {
  const [apiKey, setApiKeyState] = useState<string | null>(() => getGeminiApiKey());
  const [mockMode, setMockMode] = useState(false);
  const [apiKeyInput, setApiKeyInput] = useState("");
  const [messages, setMessages] = useState<GeminiChatMessage[]>([]);
  const [input, setInput] = useState(DEFAULT_QUESTION);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const chatEndRef = useRef<HTMLDivElement>(null);

  const mockActive = allowMock && mockMode;
  const chatReady = mockActive || Boolean(apiKey);

  useEffect(() => {
    if (!open) return;
    setApiKeyState(getGeminiApiKey());
    setMockMode(allowMock);
    setMessages([]);
    setInput(DEFAULT_QUESTION);
    setError(null);
    setApiKeyInput("");
  }, [allowMock, open]);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, loading]);

  const handleMockToggle = useCallback(
    (enabled: boolean) => {
      if (!allowMock) return;
      setMockMode(enabled);
      setError(null);
      if (!enabled && !apiKey) {
        setMessages([]);
      }
    },
    [allowMock, apiKey],
  );

  const handleSaveApiKey = useCallback(() => {
    const trimmed = apiKeyInput.trim();
    if (!trimmed) {
      setError("Introduza uma API key válida.");
      return;
    }
    setGeminiApiKey(trimmed);
    setApiKeyState(trimmed);
    setMockMode(false);
    setApiKeyInput("");
    setError(null);
  }, [apiKeyInput]);

  const handleClearApiKey = useCallback(() => {
    clearGeminiApiKey();
    setApiKeyState(null);
    setApiKeyInput("");
    setMessages([]);
    setError(null);
    if (allowMock) {
      setMockMode(true);
    }
  }, [allowMock]);

  const handleSend = useCallback(async () => {
    if (!chatReady) return;
    const question = input.trim();
    if (!question) return;
    if (!codeExcerpt.text.trim()) {
      setError("Não há código visível para analisar.");
      return;
    }

    const userMessage: GeminiChatMessage = { role: "user", text: question };
    const nextMessages = [...messages, userMessage];
    setMessages(nextMessages);
    setInput("");
    setLoading(true);
    setError(null);

    try {
      const reply = mockActive
        ? await askGeminiMock(question, codeExcerpt.lineInfo)
        : await askGemini(apiKey!, nextMessages, codeExcerpt.text);
      setMessages((prev) => [...prev, { role: "assistant", text: reply }]);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Falha ao contactar o Gemini.";
      setError(msg);
      setMessages(messages);
      setInput(question);
    } finally {
      setLoading(false);
    }
  }, [apiKey, chatReady, codeExcerpt.lineInfo, codeExcerpt.text, input, messages, mockActive]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Assistente Gemini"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="flex h-[min(640px,90vh)] w-full max-w-2xl flex-col overflow-hidden rounded-lg border border-border bg-card shadow-lg">
        <div className="flex items-center gap-2 border-b border-border px-4 py-3">
          <GeminiIcon className="h-5 w-5 shrink-0" />
          <div className="min-w-0 flex-1">
            <div className="font-mono text-xs font-semibold text-foreground">Gemini — código C</div>
            <div className="truncate text-[11px] text-muted-foreground">
              Excerto: {codeExcerpt.lineInfo}
              {codeExcerpt.truncated ? " · truncado ao limite" : ""}
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-md border border-border px-2 py-1 text-[11px] text-muted-foreground hover:bg-secondary/50 hover:text-foreground"
          >
            Fechar
          </button>
        </div>

        {!chatReady ? (
          <div className="flex flex-1 flex-col gap-4 overflow-auto p-4">
            {allowMock ? (
              <GeminiMockToggle
                id="gemini-mock-setup"
                checked={mockMode}
                onChange={handleMockToggle}
              />
            ) : null}

            {!mockMode ? (
              <>
                <p className="text-sm text-foreground">
                  Introduza a sua API key do Google AI Studio. É guardada apenas neste browser (
                  <code className="text-xs">localStorage</code>).
                </p>
                <input
                  type="password"
                  value={apiKeyInput}
                  onChange={(e) => setApiKeyInput(e.target.value)}
                  placeholder="AIza…"
                  className="w-full rounded-md border border-border bg-background px-3 py-2 font-mono text-sm text-foreground outline-none focus:ring-2 focus:ring-primary/40"
                  autoComplete="off"
                  onKeyDown={(e) => {
                    if (e.key === "Enter") handleSaveApiKey();
                  }}
                />
                {error ? <p className="text-[12px] text-destructive">{error}</p> : null}
                <div className="flex flex-wrap items-center gap-2">
                  <button
                    type="button"
                    onClick={handleSaveApiKey}
                    className="rounded-md bg-primary px-3 py-1.5 text-[12px] font-medium text-primary-foreground hover:bg-primary/90"
                  >
                    Guardar e continuar
                  </button>
                  <a
                    href="https://aistudio.google.com/apikey"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[12px] text-primary hover:underline"
                  >
                    Obter API key
                  </a>
                </div>
              </>
            ) : null}
          </div>
        ) : (
          <>
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border bg-muted/30 px-4 py-2">
              {allowMock ? (
                <GeminiMockToggle
                  id="gemini-mock-chat"
                  checked={mockMode}
                  onChange={handleMockToggle}
                />
              ) : (
                <span className="text-[11px] text-muted-foreground">API key configurada localmente</span>
              )}
              <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
                {mockActive ? <span>Resposta simulada</span> : null}
                {!mockActive && apiKey ? (
                  <button
                    type="button"
                    onClick={handleClearApiKey}
                    className="inline-flex items-center gap-1 rounded px-1.5 py-0.5 hover:bg-muted hover:text-foreground"
                    title="Remover API key"
                  >
                    <Trash2 className="h-3 w-3" />
                    Remover key
                  </button>
                ) : null}
              </div>
            </div>

            <div className="flex-1 space-y-3 overflow-auto p-4">
              {messages.length === 0 && !loading ? (
                <p className="text-[12px] text-muted-foreground">
                  Pergunte o que o excerto visível faz. O código enviado corresponde ao que está a ver no
                  painel ({codeExcerpt.lineInfo}).
                </p>
              ) : null}

              {messages.map((m, idx) => (
                <div
                  key={`${m.role}-${idx}`}
                  className={`rounded-lg border px-3 py-2 text-[12px] leading-relaxed whitespace-pre-wrap ${
                    m.role === "user"
                      ? "ml-8 border-primary/30 bg-primary/10 text-foreground"
                      : "mr-4 border-border bg-secondary/40 text-foreground"
                  }`}
                >
                  {m.text}
                </div>
              ))}

              {loading ? (
                <div className="flex items-center gap-2 text-[12px] text-muted-foreground">
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  A aguardar resposta…
                </div>
              ) : null}

              {error ? <p className="text-[12px] text-destructive">{error}</p> : null}
              <div ref={chatEndRef} />
            </div>

            <div className="border-t border-border p-3">
              <div className="flex items-end gap-2">
                <textarea
                  value={input}
                  onChange={(e) => setInput(e.target.value.slice(0, GEMINI_USER_MESSAGE_CHAR_LIMIT))}
                  rows={2}
                  placeholder="A sua pergunta…"
                  className="min-h-[52px] flex-1 resize-y rounded-md border border-border bg-background px-3 py-2 text-[12px] text-foreground outline-none focus:ring-2 focus:ring-primary/40"
                  disabled={loading}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && !e.shiftKey) {
                      e.preventDefault();
                      void handleSend();
                    }
                  }}
                />
                <button
                  type="button"
                  onClick={() => void handleSend()}
                  disabled={loading || !input.trim()}
                  className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-primary text-primary-foreground hover:bg-primary/90 disabled:opacity-40"
                  aria-label="Enviar pergunta"
                >
                  <Send className="h-4 w-4" />
                </button>
              </div>
              <div className="mt-1 text-right text-[10px] text-muted-foreground">
                {input.length}/{GEMINI_USER_MESSAGE_CHAR_LIMIT}
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
};

export default GeminiAssistDialog;
