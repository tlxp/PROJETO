"""
Módulo de Scanner YARA
Deteta padrões de malware conhecido usando regras YARA
"""

import yara
import os
from pathlib import Path
from typing import List, Dict


class YaraScanner:
    """Scanner YARA para deteção de padrões de RATs"""
    
    def __init__(self, rules_dir: str = "yara_rules"):
        self.rules_dir = Path(rules_dir)
        self.rules_dir.mkdir(exist_ok=True)
        self.rules = None
        try:
            self._compile_rules()
        except Exception as e:
            print(f"[!] Aviso: Não foi possível inicializar scanner YARA: {e}")
            print("[!] A análise continuará sem scanner YARA.")
    
    def _compile_rules(self):
        """Compila regras YARA"""
        try:
            # Criar regras básicas se não existirem
            if not any(self.rules_dir.glob("*.yar")):
                self._create_default_rules()
            
            # Compilar todas as regras
            rule_files = {}
            for rule_file in self.rules_dir.glob("*.yar"):
                rule_files[str(rule_file)] = str(rule_file)
            
            if rule_files:
                self.rules = yara.compile(filepaths=rule_files)
            else:
                self.rules = None
        except Exception as e:
            print(f"[!] Aviso: Erro ao compilar regras YARA: {e}")
            self.rules = None
    
    def scan(self, file_path: str) -> List[Dict]:
        """Executa scan YARA no ficheiro"""
        matches = []
        
        if not self.rules:
            return matches
        
        try:
            yara_matches = self.rules.match(file_path)
            
            for match in yara_matches:
                match_info = {
                    'rule': match.rule,
                    'description': match.meta.get('description', 'Sem descrição'),
                    'severity': match.meta.get('severity', 'unknown'),
                    'tags': list(match.tags),
                    'strings': []
                }
                
                # Adicionar strings encontradas (compatível com yara-python 3.x e 4.x)
                for string in match.strings:
                    if hasattr(string, 'identifier') and hasattr(string, 'instances'):
                        # yara-python 4.x: StringMatch com .identifier e .instances (StringMatchInstance)
                        for inst in string.instances:
                            data = inst.matched_data
                            if isinstance(data, bytes):
                                data = data.decode('utf-8', errors='ignore')[:100]
                            else:
                                data = str(data)[:100]
                            match_info['strings'].append({
                                'identifier': string.identifier,
                                'offset': hex(inst.offset),
                                'data': data
                            })
                    else:
                        # yara-python 3.x: tuplo (offset, identifier, data)
                        match_info['strings'].append({
                            'identifier': string[1],
                            'offset': hex(string[0]),
                            'data': (string[2].decode('utf-8', errors='ignore') if isinstance(string[2], bytes) else str(string[2]))[:100]
                        })
                
                matches.append(match_info)
        except Exception as e:
            print(f"[!] Erro ao executar scan YARA: {e}")
        
        return matches
    
    def _create_default_rules(self):
        """Cria regras YARA padrão para RATs"""
        
        # Regra para detetar características comuns de RATs
        rat_rule = """
rule RAT_Generic_Indicators
{
    meta:
        description = "Indicadores genéricos de Remote Access Trojans"
        severity = "high"
        author = "RAT Analyzer"
    
    strings:
        $s1 = "CreateRemoteThread" ascii
        $s2 = "VirtualAllocEx" ascii
        $s3 = "WriteProcessMemory" ascii
        $s4 = "socket" ascii
        $s5 = "connect" ascii
        $s6 = "WSAStartup" ascii
        $s7 = "InternetOpen" ascii
        $s8 = "HttpOpenRequest" ascii
        $s9 = "GetAsyncKeyState" ascii
        $s10 = "SetClipboardData" ascii
        
    condition:
        5 of them
}
"""
        
        # Regra para detetar strings de C&C
        c2_rule = r"""
rule C2_Communication_Patterns
{
    meta:
        description = "Padrões de comunicação C&C"
        severity = "high"
        author = "RAT Analyzer"
    
    strings:
        $s1 = /http[s]?:\/\/[a-zA-Z0-9.-]+\.(onion|bit|tk|ml|ga|cf|gq)/
        $s2 = /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{2,5}/
        $s3 = "POST /" ascii
        $s4 = "GET /" ascii
        $s5 = "User-Agent:" ascii
        
    condition:
        2 of them
}
"""
        
        # Regra para detetar técnicas de evasão
        evasion_rule = """
rule Evasion_Techniques
{
    meta:
        description = "Técnicas de evasão de detecção"
        severity = "medium"
        author = "RAT Analyzer"
    
    strings:
        $s1 = "IsDebuggerPresent" ascii
        $s2 = "CheckRemoteDebuggerPresent" ascii
        $s3 = "OutputDebugString" ascii
        $s4 = "FindWindow" ascii
        $s5 = "VirtualProtect" ascii
        $s6 = "NtProtectVirtualMemory" ascii
        
    condition:
        3 of them
}
"""
        
        # Salvar regras
        with open(self.rules_dir / "rat_generic.yar", "w") as f:
            f.write(rat_rule)
        
        with open(self.rules_dir / "c2_patterns.yar", "w") as f:
            f.write(c2_rule)
        
        with open(self.rules_dir / "evasion.yar", "w") as f:
            f.write(evasion_rule)

