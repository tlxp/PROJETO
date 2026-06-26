# --- Módulo: yara_scanner ---
# Scanner YARA: deteta padrões de malware com regras em yara_rules/.
# *Se yara-python ou regras faltarem, a análise continua sem YARA*

import logging
from pathlib import Path
from typing import List, Dict

try:
    import yara
except ImportError:  # yara-python é opcional: a análise continua sem YARA
    yara = None

logger = logging.getLogger("rat_analyzer_yara")


# --- Scanner YARA para deteção de padrões de RATs ---
class YaraScanner:

# --- Define diretório de regras e compila YARA ---
    def __init__(self, rules_dir: str = "yara_rules"):
        self.rules_dir = Path(rules_dir)
        self.rules = None
        try:
            self._compile_rules()
        except Exception:
            logger.exception("Não foi possível inicializar scanner YARA. A análise continuará sem YARA.")

    # --- Compila regras YARA a partir de rules_dir ---
    def _compile_rules(self):
        if yara is None:
            logger.warning(
                "Módulo yara-python não está instalado; a análise continuará sem scanner YARA."
            )
            return
        try:
            if not self.rules_dir.is_dir():
                logger.warning(
                    "Diretório de regras YARA não encontrado (%s); a análise continuará sem YARA.",
                    self.rules_dir,
                )
                return

            rule_files = {str(p): str(p) for p in self.rules_dir.glob("*.yar")}
            if not rule_files:
                logger.warning(
                    "Nenhuma regra YARA (*.yar) encontrada em %s; a análise continuará sem YARA.",
                    self.rules_dir,
                )
                return

            self.rules = yara.compile(filepaths=rule_files)
            logger.info("Regras YARA compiladas: %d ficheiro(s) de %s", len(rule_files), self.rules_dir)
        except Exception:
            logger.exception("Erro ao compilar regras YARA; a análise continuará sem YARA.")
            self.rules = None

    # --- Executa scan YARA no ficheiro ---
    def scan(self, file_path: str) -> List[Dict]:
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
        except Exception:
            logger.exception("Erro ao executar scan YARA em %s", file_path)

        return matches

