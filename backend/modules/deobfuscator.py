"""
Módulo de Deobfuscação
Remove ou reduz ofuscação de código (binário e código fonte C#).
Para binários: unpack UPX e/ou patch de strings XOR em .rdata/.data;
o ficheiro de saída pode ser usado pelo Ghidra.
"""

import base64
import binascii
import logging
import re
import shutil
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from artifact_naming import short_stem

logger = logging.getLogger("rat_analyzer_deobfuscator")


class Deobfuscator:
    """Deobfuscador básico para strings e código"""
    
    def __init__(self):
        self.deobfuscation_results = {}
    
    def deobfuscate(self, file_path: str) -> Dict:
        """
        Aplica técnicas de deobfuscação
        
        Nota: Para deobfuscação avançada, pode integrar ferramentas como:
        - de4dot (para .NET)
        - IDA Pro scripts
        - Ghidra scripts
        """
        results = {
            'deobfuscated_strings': [],
            'xor_strings': [],
            'base64_strings': [],
            'obfuscation_indicators': [],
            'techniques_applied': []
        }
        
        try:
            with open(file_path, 'rb') as f:
                content = f.read()

            try:
                text = content.decode('utf-8', errors='ignore')
            except (UnicodeDecodeError, ValueError):
                text = content.decode('latin-1', errors='ignore')

            results['xor_strings'] = self._detect_xor_strings(text)
            results['base64_strings'] = self._detect_base64_strings(text)
            results['obfuscation_indicators'] = self._detect_obfuscation(text)

            if results['xor_strings']:
                results['techniques_applied'].append('XOR deobfuscation')
            if results['base64_strings']:
                results['techniques_applied'].append('Base64 decoding')
            
        except Exception as e:
            results['error'] = str(e)
            logger.exception("Erro na deobfuscação de texto de %s", file_path)

        return results
    
    def _detect_xor_strings(self, text: str) -> List[str]:
        """Deteta possíveis strings XOR (assembly e C#/.NET)"""
        xor_strings = []

        xor_patterns = [
            r'xor\s+[a-zA-Z0-9_]+\s*,\s*[0-9x]+',  # Assembly XOR
            r'XOR\([^)]+\)',  # Funções XOR genéricas
            r'XorDecode\s*\(',  # C# estilo
            r'byte\s*\^\s*key',  # C# byte ^ key
            r'\(\s*byte\s*\)\s*\([^)]*\^[^)]*\)',  # (byte)(data[i] ^ key)
            r'\^\s*0x[0-9a-fA-F]+',  # XOR com literal hex
        ]
        for pattern in xor_patterns:
            matches = re.findall(pattern, text, re.IGNORECASE)
            xor_strings.extend(matches[:15])
        return list(set(xor_strings))
    
    # Nomes de tipos/metadados .NET que não são Base64 (evitar falsos positivos)
    BASE64_DOTNET_FALSE_POSITIVES = (
        'attribute', 'assembly', 'compiler', 'runtime', 'configuration',
        'version', 'framework', 'compatibility', 'generated', 'compilation',
        'refsafety', 'rules', 'requested', 'execution', 'privileges',
        'product', 'company', 'title', 'target', 'informational', 'file',
    )

    def _is_probable_base64_literal(self, s: str) -> bool:
        if not s or not isinstance(s, str):
            return False
        s = s.strip()
        if len(s) < 20 or len(s) > 4096:
            return False
        if not re.fullmatch(r"[A-Za-z0-9+/=]+", s):
            return False
        # Evita strings "normais" com slash (ex.: debug/path) que não são Base64 real.
        classes = 0
        if any(c.islower() for c in s):
            classes += 1
        if any(c.isupper() for c in s):
            classes += 1
        if any(c.isdigit() for c in s):
            classes += 1
        if "+" in s or "/" in s:
            classes += 1
        if "=" in s:
            classes += 1
        if classes < 3:
            return False
        low = s.lower()
        if any(fp in low for fp in self.BASE64_DOTNET_FALSE_POSITIVES):
            return False
        return True

    def _decode_base64_to_readable_text(self, s: str) -> str | None:
        if not self._is_probable_base64_literal(s):
            return None
        try:
            padded = s + ("=" * ((4 - (len(s) % 4)) % 4))
            raw = base64.b64decode(padded, validate=True)
        except (binascii.Error, ValueError):
            return None
        if len(raw) < 4:
            return None
        try:
            decoded = raw.decode("utf-8")
        except UnicodeDecodeError:
            return None
        printable = sum(1 for c in decoded if c.isprintable() or c in '\n\r\t')
        if len(decoded) == 0 or printable / len(decoded) < 0.85:
            return None
        if not any(c.isalpha() for c in decoded):
            return None
        return decoded
    
    def _detect_base64_strings(self, text: str) -> List[str]:
        """Deteta e decodifica strings Base64"""
        import base64
        
        base64_strings = []
        base64_pattern = r'[A-Za-z0-9+/]{20,}={0,2}'
        
        matches = re.findall(base64_pattern, text)
        
        for match in matches[:20]:  # Limitar a 20 resultados
            decoded_str = self._decode_base64_to_readable_text(match)
            if decoded_str:
                base64_strings.append({
                    'encoded': match[:50],
                    'decoded': decoded_str[:100]
                })
        
        return base64_strings
    
    def _detect_obfuscation(self, text: str) -> List[str]:
        """Deteta indicadores de ofuscação"""
        indicators = []
        
        # Padrões comuns de ofuscação (Python e C#/.NET)
        obfuscation_patterns = [
            (r'[a-zA-Z]{1,2}\s*=\s*[a-zA-Z]{1,2}\s*\+\s*[a-zA-Z]{1,2}', 'String concatenation obfuscation'),
            (r'"\s*\+\s*"[^"]*"', 'C# string concatenation'),
            (r'GetFolderPath\s*\([^)]+\)\s*\+', 'Path building with GetFolderPath'),
            (r'Path\.Combine\s*\(', 'Path.Combine (pode indicar paths sensíveis)'),
            (r'chr\(0x[0-9a-fA-F]+\)', 'Character encoding'),
            (r'eval\(', 'Eval usage'),
            (r'exec\(', 'Exec usage'),
            (r'__import__', 'Dynamic import'),
            (r'getattr\(', 'Dynamic attribute access'),
            (r'Convert\.FromBase64String', 'Base64 decode em código'),
            (r'Encoding\.UTF8\.GetString', 'Decoding de bytes para string'),
        ]
        
        for pattern, description in obfuscation_patterns:
            matches = re.findall(pattern, text, re.IGNORECASE)
            if matches:
                indicators.append(f"{description}: {len(matches)} ocorrências")
        
        return indicators
    
    def apply_xor_deobfuscation(self, data: bytes, key: int) -> bytes:
        """Aplica deobfuscação XOR com uma chave"""
        return bytes([b ^ key for b in data])
    
    def apply_multi_xor_deobfuscation(self, data: bytes, key: bytes) -> bytes:
        """Aplica deobfuscação XOR com chave multi-byte"""
        result = bytearray()
        for i, byte in enumerate(data):
            result.append(byte ^ key[i % len(key)])
        return bytes(result)

    # Deobfuscação de binário (saída = ficheiro para Ghidra)

    def _is_upx_packed(self, file_path: str) -> bool:
        """Deteta se o PE está empacotado com UPX (secções UPX0/UPX1 ou assinatura UPX!)."""
        try:
            with open(file_path, "rb") as f:
                head = f.read(8192)
            if b"UPX!" in head or b"UPX0" in head or b"UPX1" in head:
                return True
        except OSError:
            logger.debug("Falha ao ler cabeçalho UPX de %s", file_path, exc_info=True)
        try:
            import pefile
            pe = pefile.PE(file_path)
            for section in pe.sections:
                name = section.Name.decode("utf-8", errors="ignore").rstrip("\x00").upper()
                if name in ("UPX0", "UPX1", "UPX2"):
                    return True
            pe.close()
        except Exception:
            logger.debug("Falha ao inspecionar secções UPX de %s", file_path, exc_info=True)
        return False

    def _unpack_upx(self, input_path: str, output_path: str) -> Tuple[bool, str]:
        """Desempacota UPX: upx -d -o output input. Retorna (sucesso, mensagem)."""
        try:
            r = subprocess.run(
                ["upx", "-d", "-o", output_path, input_path],
                capture_output=True,
                text=True,
                timeout=120,
            )
            if r.returncode == 0 and Path(output_path).exists():
                return True, "UPX unpacked"
            return False, r.stderr or r.stdout or f"upx exit {r.returncode}"
        except FileNotFoundError:
            return False, "upx não encontrado no PATH (instale UPX para desempacotar)"
        except subprocess.TimeoutExpired:
            return False, "upx timeout"
        except Exception as e:
            return False, str(e)

    def _xor_decrypt_byte(self, data: bytes, key: int) -> bytes:
        return bytes([b ^ key for b in data])

    def _printable_ratio(self, data: bytes) -> float:
        if not data:
            return 0.0
        printable = sum(1 for b in data if 0x20 <= b <= 0x7E or b in (0x09, 0x0A, 0x0D))
        return printable / len(data)

    def _try_xor_patch_sections(self, file_path: str, output_path: str) -> Tuple[bool, int]:
        """
        Tenta encontrar blocos em .rdata/.data que parecem XOR single-byte e grava
        um novo PE com esses blocos substituídos pelo texto decodificado.
        Retorna (sucesso, número de regiões patched).
        """
        try:
            import pefile
        except ImportError:
            return False, 0
        try:
            pe = pefile.PE(file_path)
        except Exception:
            logger.debug("PE inválido para patch XOR: %s", file_path, exc_info=True)
            return False, 0
        data_section_names = (b".rdata", b".data", b".idata", b"UPX1")
        patches: List[Tuple[int, bytes, bytes]] = []  # (file_offset, original_data, new_data)
        for section in pe.sections:
            name = section.Name.rstrip(b"\x00")
            if name not in data_section_names and not name.startswith(b".rdata") and not name.startswith(b".data"):
                continue
            raw_offset = section.PointerToRawData
            raw_size = section.SizeOfRawData
            if raw_size < 8 or raw_offset <= 0:
                continue
            try:
                with open(file_path, "rb") as f:
                    f.seek(raw_offset)
                    blob = f.read(min(raw_size, 512 * 1024))
            except OSError:
                logger.debug("Falha ao ler secção em %s (offset=%s)", file_path, raw_offset, exc_info=True)
                continue
            # Janelas de 32 a 256 bytes; tentar chaves 1..255
            min_len, max_len = 32, 256
            step = 16
            for start in range(0, len(blob) - min_len, step):
                for length in (min_len, 64, 128, 256):
                    if start + length > len(blob):
                        break
                    block = blob[start : start + length]
                    best_key = None
                    best_ratio = 0.0
                    for key in range(1, 256):
                        dec = self._xor_decrypt_byte(block, key)
                        if b"\x00" in dec[:10]:
                            continue
                        r = self._printable_ratio(dec)
                        if r > best_ratio and r >= 0.85:
                            best_ratio = r
                            best_key = key
                    if best_key is not None and best_ratio >= 0.90:
                        new_data = self._xor_decrypt_byte(block, best_key)
                        file_off = raw_offset + start
                        patches.append((file_off, block, new_data))
                        break
        try:
            pe.close()
        except Exception:
            logger.debug("Falha ao fechar pefile após patch XOR: %s", file_path, exc_info=True)
        if not patches:
            return False, 0
        try:
            with open(file_path, "rb") as f:
                out_data = bytearray(f.read())
            out_parent = Path(output_path).parent
            out_parent.mkdir(parents=True, exist_ok=True)
            for (offset, _orig, new_data) in patches:
                if offset + len(new_data) <= len(out_data):
                    out_data[offset : offset + len(new_data)] = new_data
            with open(output_path, "wb") as f:
                f.write(out_data)
            # Gravar regiões obfuscadas/deobfuscadas para auditoria
            stem = short_stem(Path(file_path).stem)
            regions_path = out_parent / f"{stem}.obfuscated_binary_regions.txt"
            with open(regions_path, "w", encoding="utf-8", errors="replace") as rf:
                rf.write("# Regiões XOR patched (offset, tamanho, bytes originais hex, bytes deobfuscados hex)\n\n")
                for (offset, orig, new_data) in patches:
                    rf.write(f"--- offset 0x{offset:X} size {len(orig)} ---\n")
                    rf.write(f"original_hex: {orig.hex()}\n")
                    rf.write(f"deobfuscated_hex: {new_data.hex()}\n\n")
            return True, len(patches)
        except Exception:
            logger.exception("Falha ao gravar PE com patch XOR: %s -> %s", file_path, output_path)
            return False, 0

    def deobfuscate_binary(
        self,
        file_path: str,
        output_path: Optional[str] = None,
        output_root: str = "decompiled",
    ) -> Dict:
        """
        Produz um binário deobfuscado a partir do ficheiro dado (unpack UPX e/ou
        patch de strings XOR). O ficheiro de saída deve ser usado como entrada do Ghidra.
        :param file_path: Caminho para o .exe ou .dll
        :param output_path: Ficheiro de saída (opcional)
        :param output_root: Pasta base se output_path for None
        :return: { "success", "output_file", "techniques_applied", "error" }
        """
        result = {
            "success": False,
            "output_file": "",
            "techniques_applied": [],
            "error": "",
        }
        path = Path(file_path).resolve()
        if not path.exists():
            result["error"] = f"Ficheiro não encontrado: {path}"
            return result
        sstem = short_stem(path.stem)
        out_dir = Path(output_root).resolve() / sstem
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = Path(output_path) if output_path else (out_dir / f"{sstem}.deobfuscated{path.suffix}")

        # 1) Tentar UPX unpack
        if self._is_upx_packed(str(path)):
            try:
                ok, msg = self._unpack_upx(str(path), str(out_file))
                if ok:
                    result["success"] = True
                    result["output_file"] = str(out_file)
                    result["techniques_applied"].append("UPX unpack")
                    return result
                result["error"] = msg or "UPX desempacotagem falhou."
            except Exception as e:
                result["error"] = str(e)
            # Se UPX falhou, continuar e tentar XOR no original

        # 2) Tentar patch XOR em secções de dados (só para PE)
        if path.suffix.lower() in (".exe", ".dll"):
            ok, count = self._try_xor_patch_sections(str(path), str(out_file))
            if ok and count > 0:
                result["success"] = True
                result["output_file"] = str(out_file)
                result["techniques_applied"].append(f"XOR string patch ({count} regiões)")
                return result

        # 3) Nada aplicado: devolver cópia do original como "deobfuscated" para o Ghidra usar o mesmo ficheiro
        result["success"] = True
        result["output_file"] = str(path)
        return result

    def deobfuscate_source(self, source_path: str, output_path: Optional[str] = None) -> Dict:
        """
        Aplica deobfuscação ao código C# descompilado: decodifica Base64 em comentários,
        adiciona anotações para strings concatenadas. Escreve o resultado num ficheiro.
        :param source_path: Caminho para o ficheiro .cs consolidado (descompilado)
        :param output_path: Onde guardar o código desobfuscado (default: mesmo dir, nome .deobfuscated.cs)
        :return: { "success", "output_file", "base64_decoded", "comments_added" }
        """
        result = {"success": False, "output_file": "", "base64_decoded": 0, "error": ""}
        src = Path(source_path)
        if not src.exists():
            result["error"] = f"Ficheiro não encontrado: {source_path}"
            return result
        out = Path(output_path) if output_path else src.parent / (src.stem + ".deobfuscated.cs")
        out.parent.mkdir(parents=True, exist_ok=True)

        try:
            content = src.read_text(encoding="utf-8", errors="replace")
            lines = content.split("\n")
            new_lines = []
            base64_decoded = 0

            # Padrão: strings Base64 em C# ( "aHR0cDovL..." ou Convert.FromBase64String("...") )
            # Encontrar literais Base64 e adicionar comentário com o valor decodificado na linha seguinte
            base64_literal = re.compile(r'"([A-Za-z0-9+/]{20,}={0,2})"')
            for line in lines:
                new_lines.append(line)
                decoded_parts = []
                for m in base64_literal.finditer(line):
                    b64 = m.group(1)
                    decoded = self._decode_base64_to_readable_text(b64)
                    if decoded:
                        safe = decoded.replace("*/", "* /").replace("//", "/ /")[:150]
                        if len(decoded) > 150:
                            safe += "..."
                        decoded_parts.append(safe)
                        base64_decoded += 1
                if decoded_parts:
                    comment = "  // Decoded Base64: " + " | ".join(f'"{p}"' for p in decoded_parts[:3])
                    if len(decoded_parts) > 3:
                        comment += f" (+{len(decoded_parts) - 3} mais)"
                    new_lines.append(comment)

            out.write_text("\n".join(new_lines), encoding="utf-8")
            result["success"] = True
            result["output_file"] = str(out)
            result["base64_decoded"] = base64_decoded
        except Exception as e:
            result["error"] = str(e)
        return result

    def deobfuscate_content(self, content: str) -> str:
        """
        Aplica deobfuscação a um bloco de texto (ex.: snippet): decodifica Base64
        em comentários. Reutilizável pelo obfuscation_snippet_extractor.
        :param content: Texto (ex. várias linhas de código C#)
        :return: Texto com comentários '// Decoded Base64: ...' adicionados
        """
        if not content or not content.strip():
            return content
        lines = content.split("\n")
        new_lines = []
        base64_literal = re.compile(r'"([A-Za-z0-9+/]{20,}={0,2})"')
        for line in lines:
            new_lines.append(line)
            decoded_parts = []
            for m in base64_literal.finditer(line):
                b64 = m.group(1)
                decoded = self._decode_base64_to_readable_text(b64)
                if decoded:
                    safe = decoded.replace("*/", "* /").replace("//", "/ /")[:150]
                    if len(decoded) > 150:
                        safe += "..."
                    decoded_parts.append(safe)
            if decoded_parts:
                comment = "  // Decoded Base64: " + " | ".join(f'"{p}"' for p in decoded_parts[:3])
                if len(decoded_parts) > 3:
                    comment += f" (+{len(decoded_parts) - 3} mais)"
                new_lines.append(comment)
        return "\n".join(new_lines)

