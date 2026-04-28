"""
Módulo de Scoring de Risco
Calcula score de risco baseado em múltiplos fatores
"""

from typing import Dict, List


class RiskScorer:
    """Calcula score de risco de 0-100 baseado na análise"""
    
    # Orçamento máximo (pontos) por categoria (0-100 no total).
    #
    # Nota: estes valores DEVEM estar alinhados com:
    # - o relatório (ReportGenerator) que mostra "X/Y pontos"
    # - a documentação (README)
    # para evitar drift entre código e explicação ao utilizador.
    WEIGHTS = {
        'suspicious_imports': 15,
        'suspicious_functions': 18,
        'c2_strings': 20,
        'stealer_indicators': 15,
        'persistence_indicators': 10,
        'evasion_techniques': 15,
        'yara_matches': 20,
        'packer_indicators': 10,
        'obfuscation': 10,
        'high_entropy': 5,
    }
    
    def __init__(self):
        pass
    
    def calculate_risk(self, static_analysis: Dict, yara_matches: List[Dict], 
                      deobfuscation: Dict) -> Dict:
        """Calcula score de risco total"""
        score = 0
        details = {}
        
        # 1. Imports suspeitos
        suspicious_imports = len(static_analysis.get('suspicious_imports', []))
        import_score = min(suspicious_imports * 5, self.WEIGHTS["suspicious_imports"])
        score += import_score
        details['suspicious_imports'] = {
            'count': suspicious_imports,
            'score': import_score,
            'max': self.WEIGHTS["suspicious_imports"],
        }
        
        # 2. Funções suspeitas
        suspicious_functions = len(static_analysis.get('suspicious_functions', []))
        function_score = min(suspicious_functions * 3, self.WEIGHTS["suspicious_functions"])
        score += function_score
        details['suspicious_functions'] = {
            'count': suspicious_functions,
            'score': function_score,
            'max': self.WEIGHTS["suspicious_functions"],
        }
        
        # 3. Strings C&C
        c2_strings = len(static_analysis.get('c2_strings', []))
        c2_score = min(c2_strings * 2, self.WEIGHTS["c2_strings"])
        score += c2_score
        details['c2_strings'] = {
            'count': c2_strings,
            'score': c2_score,
            'max': self.WEIGHTS["c2_strings"],
        }

        # 3b. Indicadores de stealer
        stealer = len(static_analysis.get('stealer_indicators', []))
        stealer_score = min(stealer * 3, self.WEIGHTS["stealer_indicators"])
        score += stealer_score
        details['stealer_indicators'] = {
            'count': stealer,
            'score': stealer_score,
            'max': self.WEIGHTS["stealer_indicators"],
        }

        # 3c. Indicadores de persistência
        persistence = len(static_analysis.get('persistence_indicators', []))
        persistence_score = min(persistence * 2, self.WEIGHTS["persistence_indicators"])
        score += persistence_score
        details['persistence_indicators'] = {
            'count': persistence,
            'score': persistence_score,
            'max': self.WEIGHTS["persistence_indicators"],
        }
        
        # 4. Técnicas de evasão
        evasion_techniques = len(static_analysis.get('evasion_techniques', []))
        evasion_score = min(evasion_techniques * 3, self.WEIGHTS["evasion_techniques"])
        score += evasion_score
        details['evasion_techniques'] = {
            'count': evasion_techniques,
            'score': evasion_score,
            'max': self.WEIGHTS["evasion_techniques"],
        }
        
        # 5. Matches YARA
        yara_count = len(yara_matches)
        yara_score = min(yara_count * 5, self.WEIGHTS["yara_matches"])
        score += yara_score
        details['yara_matches'] = {
            'count': yara_count,
            'score': yara_score,
            'max': self.WEIGHTS["yara_matches"],
        }
        
        # 6. Indicadores de packer
        packer_indicators = len(static_analysis.get('packer_indicators', []))
        packer_score = min(packer_indicators * 5, self.WEIGHTS["packer_indicators"])
        score += packer_score
        details['packer_indicators'] = {
            'count': packer_indicators,
            'score': packer_score,
            'max': self.WEIGHTS["packer_indicators"],
        }
        
        # 7. Ofuscação
        obfuscation_indicators = len(deobfuscation.get('obfuscation_indicators', []))
        obfuscation_score = min(obfuscation_indicators * 2, self.WEIGHTS["obfuscation"])
        score += obfuscation_score
        details['obfuscation'] = {
            'count': obfuscation_indicators,
            'score': obfuscation_score,
            'max': self.WEIGHTS["obfuscation"],
        }
        
        # 8. Entropia alta (indicador de packing)
        entropy_data = static_analysis.get('entropy', {})
        high_entropy_count = sum(1 for e in entropy_data.values() if e > 7.0)
        entropy_score = min(high_entropy_count * 2, self.WEIGHTS["high_entropy"])
        score += entropy_score
        details['high_entropy'] = {
            'count': high_entropy_count,
            'score': entropy_score,
            'max': self.WEIGHTS["high_entropy"],
        }
        
        # Garantir que o score está entre 0 e 100
        score = min(max(score, 0), 100)
        
        # Determinar nível de risco
        level = self._get_risk_level(score)
        
        return {
            'score': score,
            'level': level,
            'details': details
        }
    
    def _get_risk_level(self, score: int) -> str:
        """Determina o nível de risco baseado no score"""
        if score >= 80:
            return "CRÍTICO"
        elif score >= 60:
            return "ALTO"
        elif score >= 40:
            return "MÉDIO"
        elif score >= 20:
            return "BAIXO"
        else:
            return "MUITO BAIXO"

