# --- Módulo: static_analyzer ---
# --- Análise estática de PE: imports suspeitos, strings C&C, evasão ---

import logging
import re
from typing import Dict, List
from urllib.parse import urlparse

import pefile

logger = logging.getLogger("rat_analyzer_static")


# --- Analisador de ficheiros PE (exe/dll) sem execução ---
class StaticAnalyzer:

    # *DLLs de rede/download — sinal mais forte que DLLs genéricas do Windows*
    SUSPICIOUS_IMPORTS = [
        "ws2_32.dll",
        "wininet.dll",
        "winhttp.dll",
        "urlmon.dll",
    ]

    # APIs com uso claramente abusável em RATs (exclui I/O e registry genéricos)
    SUSPICIOUS_FUNCTIONS = [
        "CreateRemoteThread",
        "WriteProcessMemory",
        "VirtualAllocEx",
        "SetWindowsHookEx",
        "InternetOpen",
        "InternetConnect",
        "HttpOpenRequest",
        "HttpSendRequest",
        "WSAStartup",
        "URLDownloadToFile",
        "GetAsyncKeyState",
        "SetClipboardData",
        "WinExec",
        "NtWriteVirtualMemory",
        "NtCreateThreadEx",
        "RtlCreateUserThread",
    ]

    # Padrões C&C específicos (URLs genéricas são filtradas depois)
    C2_PATTERNS = [
        r"tcp://\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{2,5}",
        r"[a-zA-Z0-9.-]+\.(onion|bit|tk|ml|ga|cf|gq)",
        r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{2,5}\b",
        r"/beacon\b",
        r"/api/collect\b",
        r"pastebin\.com/raw",
        r"https?://[a-z0-9.-]*c2\.[a-z0-9.-]+\.[a-z]{2,}",
    ]

    C2_LITERAL_INDICATORS = [
        "pastebin.com/raw",
        "c2.evil-domain",
        "/api/collect",
        "/beacon",
    ]

    C2_URL_ALLOWLIST_SUBSTRINGS = [
        "microsoft.com",
        "aka.ms",
        "w3.org",
        "schemas.microsoft.com",
        "schemas.openxmlformats.org",
        "digicert.com",
        "globalsign.com",
        "github.com",
        "githubusercontent.com",
        "dotnet",
        "nuget.org",
        "windows.com",
        "windowsupdate.com",
        "live.com",
        "office.com",
        "pkiops",
        "symcb",
        "symcd",
        "apple.com",
        "google.com",
        "mozilla.org",
        "azure.com",
        "visualstudio.com",
        "aspnetcdn.com",
    ]

    STEALER_INDICATORS = [
        "Login Data",
        "keylog_buffer",
        "Chrome\\User Data",
        "Edge\\User Data",
        "Firefox\\Profiles",
        "Telegram Desktop",
        "passwords.txt",
        "Web Data",
        "Local State",
    ]

    PERSISTENCE_INDICATORS = [
        "CurrentVersion\\Run\\",
        "CurrentVersion\\RunOnce\\",
        "Winlogon\\",
        "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run",
        "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\RunOnce",
    ]

    C2_DOTNET_FALSE_POSITIVES = [
        "attribute",
        "assembly",
        "compiler",
        "runtime",
        "requested",
        "configuration",
        "version",
        "framework",
        "identity",
        "compatibility",
        "relaxations",
        "executionlevel",
        "privileges",
        "services",
        "product",
        "fileversion",
        "informational",
        "company",
        "title",
        "targetframework",
        "refsafety",
        "generated",
        "compilation",
        "dotnet",
        "illink",
        "warnings",
    ]

    # Evasão forte: anti-VM, anti-debug de ferramentas, injeção
    EVASION_STRONG_INDICATORS = [
        "CheckRemoteDebuggerPresent",
        "NtProtectVirtualMemory",
        "NtQueryInformationProcess",
        "VBOX",
        "VMware",
        "vmtoolsd",
        "x64dbg",
        "ollydbg",
        "idaq",
        "procmon",
        "wireshark",
        "Sandboxie",
        "wine_get",
    ]

    # Evasão fraca: comum em runtimes; só conta via imports PE, não por strings
    EVASION_WEAK_IMPORTS = [
        "IsDebuggerPresent",
        "OutputDebugString",
        "GetTickCount",
        "QueryPerformanceCounter",
        "SetErrorMode",
        "SetUnhandledExceptionFilter",
        "VirtualAlloc",
        "VirtualProtect",
        "FindWindow",
        "GetForegroundWindow",
        "BlockInput",
    ]

# --- Helper interno: init   ---
    def __init__(self):
        self.results = {}

    # --- Executa análise estática completa do PE ---
    def analyze(self, file_path: str) -> Dict:
        results = {
            "suspicious_imports": [],
            "suspicious_functions": [],
            "c2_strings": [],
            "stealer_indicators": [],
            "persistence_indicators": [],
            "evasion_techniques": [],
            "sections": [],
            "entropy": {},
            "packer_indicators": [],
            "errors": [],
        }

        try:
            results["c2_strings"] = self._extract_c2_strings(file_path)
            results["stealer_indicators"] = self._extract_indicators_in_file(
                file_path, self.STEALER_INDICATORS
            )
            results["persistence_indicators"] = self._extract_indicators_in_file(
                file_path, self.PERSISTENCE_INDICATORS
            )
            results["evasion_techniques"] = self._extract_evasion_from_strings(file_path)

            pe = None
            try:
                pe = pefile.PE(file_path)
                results["suspicious_imports"] = self._analyze_imports(pe)
                results["suspicious_functions"] = self._analyze_functions(pe)
                results["evasion_techniques"] = list(
                    set(results["evasion_techniques"] + self._detect_evasion(pe))
                )
                results["sections"] = self._analyze_sections(pe)
                results["entropy"] = self._calculate_entropy(pe)
                results["packer_indicators"] = self._detect_packers(pe)
            except pefile.PEFormatError:
                pass
            finally:
                if pe is not None:
                    try:
                        pe.close()
                    except Exception:
                        logger.debug("Falha ao fechar handle pefile.", exc_info=True)

        except pefile.PEFormatError as e:
            results["errors"].append(f"Erro ao analisar PE: {e}")
            logger.warning("Erro ao analisar formato PE de %s: %s", file_path, e)
        except Exception as e:
            results["errors"].append(f"Erro inesperado: {e}")
            logger.exception("Erro inesperado na análise estática de %s", file_path)

        return results

    # --- Identifica imports de rede/download suspeitos ---
    def _analyze_imports(self, pe) -> List[str]:
        suspicious = []
        allowed = {imp.lower() for imp in self.SUSPICIOUS_IMPORTS}

        if not hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
            return suspicious

        for entry in pe.DIRECTORY_ENTRY_IMPORT:
            dll_name = entry.dll.decode("utf-8", errors="ignore").lower()
            if dll_name in allowed:
                suspicious.append(dll_name)

        return list(set(suspicious))

    # --- Identifica funções de alto risco importadas ---
    def _analyze_functions(self, pe) -> List[str]:
        suspicious = []
        allowed = set(self.SUSPICIOUS_FUNCTIONS)

        if not hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
            return suspicious

        for entry in pe.DIRECTORY_ENTRY_IMPORT:
            for imp in entry.imports:
                if imp.name:
                    func_name = imp.name.decode("utf-8", errors="ignore")
                    if func_name in allowed:
                        suspicious.append(func_name)

        return list(set(suspicious))

# --- Helper interno: read text blob ---
    def _read_text_blob(self, file_path: str) -> str:
        with open(file_path, "rb") as f:
            content = f.read()
        try:
            return content.decode("utf-8", errors="ignore")
        except (UnicodeDecodeError, ValueError):
            return content.decode("latin-1", errors="ignore")

# --- Helper interno: is false positive c2 ---
    def _is_false_positive_c2(self, candidate: str) -> bool:
        sl = candidate.lower().strip()
        if len(sl) <= 3:
            return True
        if any(fp in sl for fp in self.C2_DOTNET_FALSE_POSITIVES):
            return True
        if any(allow in sl for allow in self.C2_URL_ALLOWLIST_SUBSTRINGS):
            return True
        # Tipos .NET: c2.VoteRequestDone, c2.Aborted, etc.
        if re.match(r"^c2\.[a-z0-9_]+$", sl) and "." in sl and not re.search(r"c2\.[a-z0-9-]+\.[a-z]{2,}", sl):
            return True
        if sl in {"httpclient", "getasync", "user-agent"}:
            return True
        return False

# --- Helper interno: is high confidence url ---
    def _is_high_confidence_url(self, url: str) -> bool:
        if self._is_false_positive_c2(url):
            return False
        try:
            parsed = urlparse(url if "://" in url else f"http://{url}")
        except ValueError:
            return False
        host = (parsed.hostname or "").lower()
        if not host:
            return False
        if any(allow in host for allow in self.C2_URL_ALLOWLIST_SUBSTRINGS):
            return False
        if host in {"localhost", "127.0.0.1", "0.0.0.0"}:
            return False
        if re.match(r"^\d{1,3}(\.\d{1,3}){3}$", host):
            return True
        if any(host.endswith(tld) for tld in (".onion", ".bit", ".tk", ".ml", ".ga", ".cf", ".gq")):
            return True
        if "pastebin.com" in host:
            return True
        if re.search(r"\bc2\b", host):
            return True
        path = (parsed.path or "").lower()
        if "/beacon" in path or "/api/collect" in path:
            return True
        return False

    # --- Extrai strings C&C com filtros anti falso positivo ---
    def _extract_c2_strings(self, file_path: str) -> List[str]:
        c2_strings: List[str] = []

        try:
            text = self._read_text_blob(file_path)

            for pattern in self.C2_PATTERNS:
                c2_strings.extend(re.findall(pattern, text, flags=re.IGNORECASE))

            for lit in self.C2_LITERAL_INDICATORS:
                if lit.lower() in text.lower():
                    c2_strings.append(lit)

            for url_match in re.findall(r"https?://[^\s\"'<>]{4,}", text, flags=re.IGNORECASE):
                if self._is_high_confidence_url(url_match):
                    c2_strings.append(url_match)
        except Exception:
            logger.warning("Falha ao extrair strings C2 de %s", file_path, exc_info=True)

        filtered = []
        seen = set()
        for raw in c2_strings:
            s = raw.strip()
            if not s or s in seen or self._is_false_positive_c2(s):
                continue
            seen.add(s)
            filtered.append(s)

        return filtered[:50]

    # --- Procura indicadores de stealer/persistência no ficheiro ---
    def _extract_indicators_in_file(self, file_path: str, indicators: List[str]) -> List[str]:
        found = []
        try:
            text = self._read_text_blob(file_path)
            text_lower = text.lower()
            for ind in indicators:
                if ind.lower() in text_lower:
                    found.append(ind)
        except Exception:
            logger.debug("Falha ao procurar indicadores em %s", file_path, exc_info=True)
        return list(set(found))

    # --- Deteta evasão por strings (anti-VM/anti-análise) ---
    def _extract_evasion_from_strings(self, file_path: str) -> List[str]:
        found = []
        try:
            text = self._read_text_blob(file_path)
            for ind in self.EVASION_STRONG_INDICATORS:
                if ind in text:
                    found.append(ind)
        except Exception:
            logger.debug("Falha ao procurar técnicas de evasão em %s", file_path, exc_info=True)
        return list(set(found))

    # --- Deteta técnicas de evasão via imports PE ---
    def _detect_evasion(self, pe) -> List[str]:
        evasion: List[str] = []
        weak_hits: List[str] = []
        if not hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
            return evasion

        strong = set(self.EVASION_STRONG_INDICATORS)
        weak = set(self.EVASION_WEAK_IMPORTS)

        for entry in pe.DIRECTORY_ENTRY_IMPORT:
            for imp in entry.imports:
                if not imp.name:
                    continue
                func_name = imp.name.decode("utf-8", errors="ignore")
                if func_name in strong:
                    evasion.append(func_name)
                elif func_name in weak:
                    weak_hits.append(func_name)

        evasion = list(set(evasion))
        # APIs fracas só contam em conjunto (≥3), típico de packers/malware — não de runtime .NET isolado
        if len(set(weak_hits)) >= 3:
            evasion.extend(sorted(set(weak_hits)))
        return list(set(evasion))

    # --- Analisa secções do PE (nome, tamanho, entropia) ---
    def _analyze_sections(self, pe) -> List[Dict]:
        sections = []

        for section in pe.sections:
            section_info = {
                "name": section.Name.decode("utf-8", errors="ignore").rstrip("\x00"),
                "virtual_address": hex(section.VirtualAddress),
                "virtual_size": section.Misc_VirtualSize,
                "raw_size": section.SizeOfRawData,
                "characteristics": hex(section.Characteristics),
            }
            sections.append(section_info)

        return sections

    # --- Calcula entropia das secções (indicador de packing) ---
    def _calculate_entropy(self, pe) -> Dict:
        import math

        entropy_data = {}

        for section in pe.sections:
            section_name = section.Name.decode("utf-8", errors="ignore").rstrip("\x00")
            section_data = section.get_data()

            if len(section_data) == 0:
                continue

            entropy = 0
            for x in range(256):
                p_x = float(section_data.count(bytes([x]))) / len(section_data)
                if p_x > 0:
                    entropy += -p_x * math.log2(p_x)

            entropy_data[section_name] = round(entropy, 2)

        return entropy_data

    # --- Deteta indicadores de packers conhecidos ---
    def _detect_packers(self, pe) -> List[str]:
        packers = []

        entropy_data = self._calculate_entropy(pe)
        for section, entropy in entropy_data.items():
            if entropy > 7.0:
                packers.append(f"Alta entropia na secção {section} ({entropy})")

        suspicious_section_names = [".packed", ".upx", ".aspack", ".nspack"]
        for section in pe.sections:
            section_name = section.Name.decode("utf-8", errors="ignore").rstrip("\x00").lower()
            if any(sus in section_name for sus in suspicious_section_names):
                packers.append(f"Secção suspeita: {section_name}")

        return packers
