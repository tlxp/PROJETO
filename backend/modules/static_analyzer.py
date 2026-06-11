"""
Módulo de Análise Estática
Identifica imports suspeitos, strings de C&C, técnicas de evasão
"""

import logging
import re
from typing import Dict, List

import pefile

logger = logging.getLogger("rat_analyzer_static")


class StaticAnalyzer:
    """Analisa ficheiros PE (exe/dll) sem executá-los"""
    
    # Imports suspeitos comuns em RATs
    SUSPICIOUS_IMPORTS = [
        'ws2_32.dll', 'wininet.dll', 'winhttp.dll',  # Rede
        'advapi32.dll', 'kernel32.dll',  # Funções de sistema
        'user32.dll', 'gdi32.dll',  # Manipulação de UI
        'crypt32.dll', 'wincrypt.dll',  # Criptografia
        'ntdll.dll',  # Chamadas de sistema de baixo nível
        'shell32.dll', 'shlwapi.dll',  # Operações de shell
        'urlmon.dll', 'ole32.dll', 'oleaut32.dll',  # COM/URL
    ]
    
    # Funções suspeitas específicas
    SUSPICIOUS_FUNCTIONS = [
        'CreateRemoteThread', 'WriteProcessMemory', 'VirtualAllocEx',
        'SetWindowsHookEx', 'RegisterHotKey', 'SetTimer',
        'InternetOpen', 'InternetConnect', 'HttpOpenRequest',
        'WSAStartup', 'socket', 'connect', 'send', 'recv',
        'CryptEncrypt', 'CryptDecrypt', 'CryptAcquireContext',
        'RegCreateKeyEx', 'RegSetValueEx', 'RegOpenKeyEx',
        'CreateFile', 'WriteFile', 'ReadFile',
        'FindWindow', 'GetAsyncKeyState', 'SetClipboardData',
        'URLDownloadToFile', 'ShellExecute', 'WinExec',
    ]
    
    # Padrões de strings de C&C
    C2_PATTERNS = [
        r'http[s]?://[^\s"\'<>]+',  # URLs HTTP/HTTPS
        r'tcp://\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{2,5}',  # tcp://IP:port
        r'[a-zA-Z0-9.-]+\.(onion|bit|tk|ml|ga|cf|gq)',  # Domínios suspeitos
        r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{2,5}',  # IP:Porta
        r'/beacon',  # endpoint beacon
        r'/api/collect',  # endpoint exfiltração
        r'pastebin\.com/raw',  # exfiltração via pastebin
        r'c2\.[a-zA-Z0-9.-]+',  # subdomínio c2
    ]

    # Strings literais C2 (para pesquisa direta no binário)
    C2_LITERAL_INDICATORS = [
        'beacon', '/api/collect', 'pastebin.com', 'c2.evil-domain',
        'HttpClient', 'GetAsync', 'User-Agent',
    ]

    # Padrões de stealer (credenciais, keylog, screenshots)
    STEALER_INDICATORS = [
        'Login Data', 'Cookies', 'User Data', 'keylog_buffer', 'screens',
        'GetAsyncKeyState', 'SetWindowsHookEx', 'SetClipboardData',
        'Chrome\\User Data', 'Edge\\User Data', 'Firefox\\Profiles',
        'Discord', 'Telegram Desktop', 'passwords.txt',
    ]

    # Padrões de persistência (registro, Run, RunOnce)
    PERSISTENCE_INDICATORS = [
        'CurrentVersion\\Run', 'CurrentVersion\\RunOnce',
        'Winlogon', 'RegSetValueEx', 'RegCreateKeyEx', 'RegOpenKeyEx',
        'SOFTWARE\\Microsoft\\Windows\\CurrentVersion',
    ]

    # Termos que indicam metadados .NET / assembly legítimos (excluir de C2)
    C2_DOTNET_FALSE_POSITIVES = [
        'attribute', 'assembly', 'compiler', 'runtime', 'requested',
        'configuration', 'version', 'framework', 'identity', 'compatibility',
        'relaxations', 'executionlevel', 'privileges', 'services',
        'product', 'fileversion', 'informational', 'company', 'title',
        'targetframework', 'refsafety', 'generated', 'compilation',
    ]

    # Técnicas de evasão comuns (APIs e comportamentos)
    EVASION_INDICATORS = [
        'VirtualAlloc', 'VirtualProtect', 'NtProtectVirtualMemory',
        'IsDebuggerPresent', 'CheckRemoteDebuggerPresent',
        'OutputDebugString', 'GetTickCount', 'QueryPerformanceCounter',
        'FindWindow', 'GetForegroundWindow', 'BlockInput',
        'SetErrorMode', 'SetUnhandledExceptionFilter',
        'Debugger', 'IsAttached', 'VBOX', 'VMware', 'vmtoolsd',
        'x64dbg', 'ollydbg', 'idaq', 'procmon', 'wireshark',
    ]
    
    def __init__(self):
        self.results = {}
    
    def analyze(self, file_path: str) -> Dict:
        """Executa análise estática completa"""
        results = {
            'suspicious_imports': [],
            'suspicious_functions': [],
            'c2_strings': [],
            'stealer_indicators': [],
            'persistence_indicators': [],
            'evasion_techniques': [],
            'sections': [],
            'entropy': {},
            'packer_indicators': [],
            'errors': []
        }

        try:
            # Análise de strings no binário (funciona mesmo sem PE válido para .NET)
            results['c2_strings'] = self._extract_c2_strings(file_path)
            results['stealer_indicators'] = self._extract_indicators_in_file(
                file_path, self.STEALER_INDICATORS
            )
            results['persistence_indicators'] = self._extract_indicators_in_file(
                file_path, self.PERSISTENCE_INDICATORS
            )
            results['evasion_techniques'] = self._extract_evasion_from_strings(file_path)

            pe = None
            try:
                pe = pefile.PE(file_path)
                # Análise de imports (PE nativo)
                results['suspicious_imports'] = self._analyze_imports(pe)
                results['suspicious_functions'] = self._analyze_functions(pe)
                # Evasão também via imports (complementar)
                results['evasion_techniques'] = list(set(
                    results['evasion_techniques'] + self._detect_evasion(pe)
                ))
                # Análise de secções
                results['sections'] = self._analyze_sections(pe)
                results['entropy'] = self._calculate_entropy(pe)
                results['packer_indicators'] = self._detect_packers(pe)
            except pefile.PEFormatError:
                pass  # .NET assemblies podem ter formato diferente; strings já foram analisadas
            finally:
                if pe is not None:
                    try:
                        pe.close()
                    except Exception:
                        logger.debug("Falha ao fechar handle pefile.", exc_info=True)

        except pefile.PEFormatError as e:
            results['errors'].append(f"Erro ao analisar PE: {e}")
            logger.warning("Erro ao analisar formato PE de %s: %s", file_path, e)
        except Exception as e:
            results['errors'].append(f"Erro inesperado: {e}")
            logger.exception("Erro inesperado na análise estática de %s", file_path)

        return results
    
    def _analyze_imports(self, pe) -> List[str]:
        """Identifica imports suspeitos"""
        suspicious = []
        
        if not hasattr(pe, 'DIRECTORY_ENTRY_IMPORT'):
            return suspicious
        
        for entry in pe.DIRECTORY_ENTRY_IMPORT:
            dll_name = entry.dll.decode('utf-8', errors='ignore').lower()
            if dll_name in [imp.lower() for imp in self.SUSPICIOUS_IMPORTS]:
                suspicious.append(dll_name)
        
        return list(set(suspicious))
    
    def _analyze_functions(self, pe) -> List[str]:
        """Identifica funções suspeitas"""
        suspicious = []
        
        if not hasattr(pe, 'DIRECTORY_ENTRY_IMPORT'):
            return suspicious
        
        for entry in pe.DIRECTORY_ENTRY_IMPORT:
            for imp in entry.imports:
                if imp.name:
                    func_name = imp.name.decode('utf-8', errors='ignore')
                    if func_name in self.SUSPICIOUS_FUNCTIONS:
                        suspicious.append(func_name)
        
        return list(set(suspicious))
    
    def _extract_c2_strings(self, file_path: str) -> List[str]:
        """Extrai strings que podem ser C&C"""
        c2_strings = []
        
        try:
            with open(file_path, 'rb') as f:
                content = f.read()
                # Tentar decodificar como ASCII/UTF-8
                try:
                    text = content.decode('utf-8', errors='ignore')
                except (UnicodeDecodeError, ValueError):
                    text = content.decode('latin-1', errors='ignore')

                # Procurar padrões C&C
                for pattern in self.C2_PATTERNS:
                    matches = re.findall(pattern, text)
                    c2_strings.extend(matches)
        except Exception:
            logger.warning("Falha ao extrair strings C2 de %s", file_path, exc_info=True)
        
        # Indicadores literais C2 no ficheiro
        try:
            with open(file_path, 'rb') as f:
                text = f.read().decode('utf-8', errors='ignore')
            for lit in self.C2_LITERAL_INDICATORS:
                if lit in text:
                    c2_strings.append(lit)
        except Exception:
            logger.debug("Falha ao procurar indicadores literais C2 em %s", file_path, exc_info=True)

        # Remover duplicados e filtrar strings muito curtas
        c2_strings = [s for s in set(c2_strings) if len(s) > 3]
        # Excluir falsos positivos: metadados .NET / nomes de assembly
        c2_strings = [
            s for s in c2_strings
            if not any(
                fp in s.lower() for fp in self.C2_DOTNET_FALSE_POSITIVES
            )
        ]
        return c2_strings[:50]  # Limitar a 50 resultados
    
    def _extract_indicators_in_file(self, file_path: str, indicators: List[str]) -> List[str]:
        """Procura indicadores (stealer, persistência) no conteúdo do ficheiro."""
        found = []
        try:
            with open(file_path, 'rb') as f:
                content = f.read()
            text = content.decode('utf-8', errors='ignore')
            for ind in indicators:
                if ind in text:
                    found.append(ind)
        except Exception:
            logger.debug("Falha ao procurar indicadores em %s", file_path, exc_info=True)
        return list(set(found))

    def _extract_evasion_from_strings(self, file_path: str) -> List[str]:
        """Deteta técnicas de evasão através de strings no binário (útil para .NET)."""
        found = []
        try:
            with open(file_path, 'rb') as f:
                content = f.read()
            text = content.decode('utf-8', errors='ignore')
            for ind in self.EVASION_INDICATORS:
                if ind in text:
                    found.append(ind)
        except Exception:
            logger.debug("Falha ao procurar técnicas de evasão em %s", file_path, exc_info=True)
        return list(set(found))

    def _detect_evasion(self, pe) -> List[str]:
        """Deteta técnicas de evasão via imports PE"""
        evasion = []
        if not hasattr(pe, 'DIRECTORY_ENTRY_IMPORT'):
            return evasion
        for entry in pe.DIRECTORY_ENTRY_IMPORT:
            for imp in entry.imports:
                if imp.name:
                    func_name = imp.name.decode('utf-8', errors='ignore')
                    if func_name in self.EVASION_INDICATORS:
                        evasion.append(func_name)
        return list(set(evasion))
    
    def _analyze_sections(self, pe) -> List[Dict]:
        """Analisa secções do PE"""
        sections = []
        
        for section in pe.sections:
            section_info = {
                'name': section.Name.decode('utf-8', errors='ignore').rstrip('\x00'),
                'virtual_address': hex(section.VirtualAddress),
                'virtual_size': section.Misc_VirtualSize,
                'raw_size': section.SizeOfRawData,
                'characteristics': hex(section.Characteristics),
            }
            sections.append(section_info)
        
        return sections
    
    def _calculate_entropy(self, pe) -> Dict:
        """Calcula entropia das secções (indicador de packing)"""
        import math
        
        entropy_data = {}
        
        for section in pe.sections:
            section_name = section.Name.decode('utf-8', errors='ignore').rstrip('\x00')
            section_data = section.get_data()
            
            if len(section_data) == 0:
                continue
            
            # Calcular entropia
            entropy = 0
            for x in range(256):
                p_x = float(section_data.count(bytes([x]))) / len(section_data)
                if p_x > 0:
                    entropy += - p_x * math.log2(p_x)
            
            entropy_data[section_name] = round(entropy, 2)
        
        return entropy_data
    
    def _detect_packers(self, pe) -> List[str]:
        """Deteta indicadores de packers conhecidos"""
        packers = []
        
        # Verificar entropia alta (geralmente > 7.0 indica packing)
        entropy_data = self._calculate_entropy(pe)
        for section, entropy in entropy_data.items():
            if entropy > 7.0:
                packers.append(f"Alta entropia na secção {section} ({entropy})")
        
        # Verificar nomes de secções suspeitos
        suspicious_section_names = ['.packed', '.upx', '.aspack', '.nspack']
        for section in pe.sections:
            section_name = section.Name.decode('utf-8', errors='ignore').rstrip('\x00').lower()
            if any(sus in section_name for sus in suspicious_section_names):
                packers.append(f"Secção suspeita: {section_name}")
        
        return packers

