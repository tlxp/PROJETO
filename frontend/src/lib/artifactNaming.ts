// --- Módulo: artifactNaming.ts ---
// Nomes curtos e seguros para artefatos (hash FNV-1a).

// --- Hash e slug ---
function fnv1a32(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

export function hash8(text: string): string {
  return fnv1a32(text).toString(16).padStart(8, "0").slice(0, 8);
}

export function slugify(text: string, maxLen = 32): string {
  const raw = (text ?? "").trim();
  if (!raw) return "x";
  const s = raw
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\w.-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
  const out = s || "x";
  return out.length > maxLen ? out.slice(0, maxLen) : out;
}

export function buildShortFileName(args: {
  baseName: string;
  kind: string;
  parts: string[];
  ext: string;
  maxTotal?: number;
}): string {
  const maxTotal = Math.max(40, Math.floor(args.maxTotal ?? 120));
  const ext = (args.ext || "").startsWith(".") ? args.ext : `.${args.ext || "txt"}`;
  const base = slugify(args.baseName, 28);
  const kind = slugify(args.kind, 18);
  const compactParts = args.parts.map((p) => slugify(p, 22));
  const fullKey = [args.baseName, args.kind, ...args.parts].join("|");
  const h = hash8(fullKey);

  // *Formato completo: base.kind.p1.p2.hash.ext*
  let name = [base, kind, ...compactParts, h].filter(Boolean).join(".") + ext;
  if (name.length <= maxTotal) return name;

  // *Reduz para base.kind.hash.ext*
  name = [base, kind, h].filter(Boolean).join(".") + ext;
  if (name.length <= maxTotal) return name;

  // *Último recurso: h<ext>*
  return `h${h}${ext}`.slice(0, maxTotal);
}

