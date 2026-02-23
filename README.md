# RAT Analyzer

Ferramenta de Análise Automática de DLLs e Executáveis para Detecção de RATs (Remote Access Trojans)

## Descrição

Este projeto foi desenvolvido no âmbito de um projeto de licenciatura. A ferramenta combina análise estática avançada com detecção de padrões YARA para identificar possíveis Remote Access Trojans em ficheiros executáveis (.exe) e bibliotecas dinâmicas (.dll).

## Funcionalidades

- **Análise Estática**: Identifica imports suspeitos, strings de Command & Control, técnicas de evasão e padrões de malware conhecido
- **Scanner YARA**: Detecta padrões de RATs conhecidos usando regras YARA customizáveis
- **Deobfuscação**: Aplica técnicas básicas de deobfuscação para revelar código ofuscado
- **Scoring de Risco**: Calcula um score de risco de 0-100 baseado em múltiplos fatores
- **Relatórios Detalhados**: Gera relatórios completos em formato texto

## Requisitos

- Python 3.7+
- Bibliotecas Python (ver `requirements.txt`)

## Instalação

1. Clone ou baixe este repositório

2. Instale as dependências:
```bash
pip install -r requirements.txt
```

3. **Nota sobre YARA**: Para usar o scanner YARA, é necessário instalar a biblioteca YARA no sistema:
   - **Windows**: Baixe de https://github.com/VirusTotal/yara/releases
   - **Linux**: `sudo apt-get install yara` ou `sudo yum install yara`
   - **macOS**: `brew install yara`

4. **Opcional — Decompilação para pseudo-C (binários nativos)**: Para converter assembly em código C legível (Ghidra):
   - Instale [Ghidra 12+](https://github.com/NationalSecurityAgency/ghidra/releases) e descompacte numa pasta (ex.: `C:\ghidra_12.0_PUBLIC`).
   - Defina a variável de ambiente `GHIDRA_INSTALL_DIR` com o caminho dessa pasta.
   - O pacote `pyghidra` (em `requirements.txt`) permite usar o decompilador Ghidra a partir do Python. Sem Ghidra instalado, a análise continua a funcionar; apenas não será gerado o ficheiro pseudo-C para binários nativos.

## Uso

### Interface gráfica (recomendado para projetos .NET)
Arraste um ficheiro `.cs` (ou selecione-o), compile o projeto e escolha analisar o `.exe` ou o `.dll`:

```bash
pip install -r requirements.txt   # inclui windnd para drag-and-drop no Windows
python rat_analyzer_gui.py
```

1. Arraste um ficheiro **.cs** para a janela (ou use "Procurar ficheiro .cs")
2. Clique em **Compilar (dotnet publish)** para gerar o .exe e .dll
3. Escolha **Analisar o .exe** ou **Analisar o .dll**
4. Clique em **Executar análise RAT**. Os relatórios são guardados em `reports/`

### Análise básica (linha de comandos):
```bash
python rat_analyzer.py caminho/para/ficheiro.exe
```

### Com opções:
```bash
python rat_analyzer.py caminho/para/ficheiro.dll -o relatorios/ -v
```

### Parâmetros:
- `file`: Caminho para o ficheiro .exe ou .dll a analisar (obrigatório)
- `-o, --output`: Directório de saída para relatórios (padrão: `reports`)
- `-v, --verbose`: Modo verboso com informações detalhadas

### Limpar caches e ficheiros temporários
Remove apenas caches e artefactos gerados (não apaga código fonte nem relatórios):

```bash
python clean.py
```

Apaga: `__pycache__/`, `.pytest_cache`, `*.pyc`/`*.pyo`, `programa/bin/`, `programa/obj/`, `decompiled/`. Para simular sem apagar, use `python clean.py --dry-run`.

## Estrutura do Projeto

```
PROJETO/
├── config.py                # Configuração central (caminhos do projeto)
├── rat_analyzer.py          # Entrada CLI – análise de .exe/.dll
├── rat_analyzer_gui.py      # Entrada GUI – arrastar .cs, compilar e analisar
├── modules/                 # Módulos do analisador
│   ├── __init__.py
│   ├── static_analyzer.py   # Análise estática (imports, strings, evasão)
│   ├── yara_scanner.py      # Scanner YARA
│   ├── deobfuscator.py      # Deobfuscação básica
│   ├── dotnet_decompiler.py # Descompilação .NET (ILSpy)
│   ├── risk_scorer.py       # Cálculo de score de risco
│   └── report_generator.py  # Geração de relatórios
├── yara_rules/              # Regras YARA (.yar)
├── reports/                 # Relatórios gerados (criada automaticamente)
├── decompiled/              # Código C# descompilado (ILSpy)
├── programa/                # Projeto .NET de exemplo para testes
├── requirements.txt
└── README.md
```

Os caminhos `reports/`, `decompiled/` e `yara_rules/` estão definidos em `config.py`; pode alterá-los aí se precisar.

## Módulos

### Static Analyzer
Analisa ficheiros PE sem executá-los:
- Identifica imports suspeitos (networking, criptografia, sistema)
- Detecta funções suspeitas (CreateRemoteThread, socket, etc.)
- Extrai strings de C&C (URLs, IPs, tokens)
- Identifica técnicas de evasão (anti-debug, anti-VM)
- Calcula entropia das secções (detecção de packing)
- Detecta indicadores de packers conhecidos

### YARA Scanner
- Compila e executa regras YARA
- Detecta padrões genéricos de RATs
- Identifica padrões de comunicação C&C
- Detecta técnicas de evasão

### Deobfuscator
- Detecta strings XOR
- Decodifica strings Base64
- Identifica indicadores de ofuscação

### Risk Scorer
Calcula score de risco baseado em:
- Imports suspeitos (15 pontos)
- Funções suspeitas (20 pontos)
- Strings C&C (25 pontos)
- Técnicas de evasão (15 pontos)
- Matches YARA (20 pontos)
- Indicadores de packer (10 pontos)
- Ofuscação (10 pontos)
- Entropia alta (5 pontos)

**Níveis de Risco:**
- 80-100: CRÍTICO
- 60-79: ALTO
- 40-59: MÉDIO
- 20-39: BAIXO
- 0-19: MUITO BAIXO

## Integração com Ferramentas Externas

### Conversão de EXE/DLL para Source Code
O projeto está preparado para integrar ferramentas que convertem executáveis para código fonte. Algumas opções:

- **Ghidra** (gratuito): Descompilador avançado
- **IDA Pro** (comercial): Descompilador profissional
- **Radare2** (gratuito): Framework de análise reversa
- **RetDec** (gratuito): Descompilador online/offline

Para integrar, modifique o módulo `static_analyzer.py` ou crie um novo módulo que processe o código fonte gerado.

### Deobfuscadores Avançados
Para deobfuscação mais avançada, pode integrar:
- **de4dot** (para .NET)
- Scripts customizados para Ghidra/IDA
- Ferramentas específicas de deobfuscação

## Personalização

### Adicionar Regras YARA
Coloque ficheiros `.yar` no directório `yara_rules/`. O scanner compilará automaticamente todas as regras.

### Ajustar Pesos do Score
Edite `modules/risk_scorer.py` para ajustar os pesos dos diferentes fatores.

### Adicionar Padrões de Detecção
- **Imports suspeitos**: Edite `SUSPICIOUS_IMPORTS` em `static_analyzer.py`
- **Funções suspeitas**: Edite `SUSPICIOUS_FUNCTIONS` em `static_analyzer.py`
- **Padrões C&C**: Edite `C2_PATTERNS` em `static_analyzer.py`

## Limitações

- Análise estática apenas (não executa o ficheiro)
- Deobfuscação básica (pode não funcionar com ofuscação avançada)
- Requer instalação de YARA no sistema
- Regras YARA básicas incluídas (recomenda-se adicionar mais)

## Melhorias Futuras

- [ ] Integração com ferramentas de descompilação (Ghidra, IDA)
- [ ] Deobfuscação avançada
- [ ] Análise comportamental (sandbox)
- [ ] Suporte para mais formatos de ficheiro
- [ ] Base de dados de assinaturas de malware conhecido
- [ ] Análise de rede (tráfego C&C)

## Licença

Este projeto foi desenvolvido no âmbito académico.

## Autor

Desenvolvido como projeto de licenciatura.

## Contribuições

Sugestões e melhorias são bem-vindas!

