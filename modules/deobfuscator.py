"""
Módulo de Deobfuscação
Remove ou reduz ofuscação de código (binário e código fonte C#)
"""

import base64
import re
from pathlib import Path
from typing import Dict, List, Optional


class Deobfuscator:
    """Deobfuscador básico para strings e código"""
    
    def __init__(self):
        self.deobfuscation_results = {}
    
    def deobfuscate(self, file_path: str) -> Dict:
        """
        Aplica técnicas de deobfuscação
        
        Nota: Para deobfuscação avançada, pode integrar ferramentas como:
        - unpyc37 (para Python)
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
            
            # Tentar decodificar como texto
            try:
                text = content.decode('utf-8', errors='ignore')
            except:
                text = content.decode('latin-1', errors='ignore')
            
            # Detectar e deobfuscar strings XOR
            results['xor_strings'] = self._detect_xor_strings(text)
            
            # Detectar strings Base64
            results['base64_strings'] = self._detect_base64_strings(text)
            
            # Detectar indicadores de ofuscação
            results['obfuscation_indicators'] = self._detect_obfuscation(text)
            
            # Aplicar técnicas de deobfuscação
            if results['xor_strings']:
                results['techniques_applied'].append('XOR deobfuscation')
            if results['base64_strings']:
                results['techniques_applied'].append('Base64 decoding')
            
        except Exception as e:
            results['error'] = str(e)
        
        return results
    
    def _detect_xor_strings(self, text: str) -> List[str]:
        """Detecta possíveis strings XOR (assembly e C#/.NET)"""
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
    
    def _detect_base64_strings(self, text: str) -> List[str]:
        """Detecta e decodifica strings Base64"""
        import base64
        
        base64_strings = []
        base64_pattern = r'[A-Za-z0-9+/]{20,}={0,2}'
        
        matches = re.findall(base64_pattern, text)
        
        for match in matches[:20]:  # Limitar a 20 resultados
            # Excluir falsos positivos: Base64 real usa + ou / ou termina em =
            # Nomes .NET são só A-Za-z0-9 sem +/=
            if '/' not in match and '+' not in match and not match.strip().endswith('='):
                continue
            # Excluir strings que parecem nomes de tipos .NET
            low = match.lower()
            if any(fp in low for fp in self.BASE64_DOTNET_FALSE_POSITIVES):
                continue
            try:
                # Tentar decodificar
                decoded = base64.b64decode(match + '==')  # Adicionar padding se necessário
                decoded_str = decoded.decode('utf-8', errors='ignore')
                # Ignorar se o resultado for maioritariamente não imprimível (lixo)
                printable = sum(1 for c in decoded_str if c.isprintable() or c in '\n\r\t')
                if len(decoded_str) > 0 and printable / len(decoded_str) < 0.7:
                    continue
                # Verificar se parece ser uma string útil (não apenas caracteres aleatórios)
                if len(decoded_str) > 3 and any(c.isalnum() for c in decoded_str):
                    base64_strings.append({
                        'encoded': match[:50],
                        'decoded': decoded_str[:100]
                    })
            except Exception:
                pass
        
        return base64_strings
    
    def _detect_obfuscation(self, text: str) -> List[str]:
        """Detecta indicadores de ofuscação"""
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
                    if any(fp in b64.lower() for fp in self.BASE64_DOTNET_FALSE_POSITIVES):
                        continue
                    try:
                        raw = base64.b64decode(b64 + "==")
                        decoded = raw.decode("utf-8", errors="replace")
                        if len(decoded) > 2 and sum(1 for c in decoded if c.isprintable() or c in "\n\r\t") / max(len(decoded), 1) >= 0.6:
                            safe = decoded.replace("*/", "* /").replace("//", "/ /")[:150]
                            if len(decoded) > 150:
                                safe += "..."
                            decoded_parts.append(safe)
                            base64_decoded += 1
                    except Exception:
                        pass
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

