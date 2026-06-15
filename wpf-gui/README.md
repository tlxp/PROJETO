# Desktop WPF - RAT Analyzer

Aplicação **Windows** (.NET 8 · WPF) - ponto de entrada gráfico do ecossistema: arranque automático do backend e frontend, **análise estática** via API e **análise comportamental** na sandbox Hyper-V (**Caminho B**).

Visão geral: [README principal](../README.md) · sandbox: [`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md) · índice: [`docs/README.md`](../docs/README.md).

## Índice

- [Funcionalidades](#funcionalidades)
- [Requisitos](#requisitos)
- [Compilar e executar](#compilar-e-executar)
- [Fluxo de utilização](#fluxo-de-utilização)
- [Credenciais do guest](#credenciais-do-guest)
- [Variáveis de ambiente](#variáveis-de-ambiente)
- [Estrutura](#estrutura)
- [Segurança](#segurança)
- [Resolução de problemas](#resolução-de-problemas)

## Funcionalidades

| Fluxo | O que faz |
|-------|-----------|
| **Análise estática** | Envia a amostra ao backend FastAPI, obtém `jobId` e abre o browser em `http://localhost:8080/resultados?jobId=…`. |
| **Análise comportamental** | Orquestra `scripts/hyperv-sandbox/` (`04-Run-Sample.ps1`): restore snapshot → execução na VM → relatório por COM1 / Copy-VMFile. |
| **Arranque integrado** | `StartupSequence` verifica ou inicia uvicorn (porta **8000**) e `npm run dev` (porta **8080**). |
| **Bootstrap de dependências** | Instala/valida Python, npm, Ghidra, ILSpy, Java e ADK do sandbox (verificação SHA-256 opcional). |
| **Manutenção de storage** | Janela para estimar/limpar artefatos do backend (`/api/storage/*`). |
| **Credenciais guest** | Diálogo `VmGuestCredentialsWindow` para PowerShell Direct na VM. |

> A análise dinâmica pelo WPF usa o **pipeline serial PowerShell** (Caminho B), **não** o driver `hyperv.py` do backend nem o vm-agent HTTP (Caminho A).

### Janelas principais

| Vista | Função |
|-------|--------|
| `LoadingView` | Arranque - `StartupSequence` + bootstrap de dependências |
| `MainDashboardView` | Drop de ficheiros, escolha estática vs comportamental |
| `VmAnalysisWindow` | Log em tempo real do `04-Run-Sample.ps1` |
| `VmGuestCredentialsWindow` | Utilizador/password do guest (sessão ou env) |
| Diálogos de storage | Estimativa, limpeza, arquivo e purge via API |

## Requisitos

- **Windows 10/11 Pro** ou Enterprise (ou Server) com **Hyper-V** (análise comportamental).
- **.NET 8 SDK** (compilar) ou runtime (`.exe` publicado).
- **Execução como Administrador** - obrigatória (Hyper-V, scripts PowerShell, firewall).
- **Python 3.10+** e **Node.js 18+** no PATH (arranque automático backend/frontend).
- Sandbox preparado - ver [`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md).

## Compilar e executar

```powershell
# Na raiz do repositório
dotnet build RatAnalyzer.sln -c Release
dotnet run --project wpf-gui
```

> Execute **como Administrador**. Sem elevação, a app termina no arranque (`App.xaml.cs`).

Publicação autónoma:

```powershell
dotnet publish wpf-gui -c Release -r win-x64 --self-contained false
```

## Fluxo de utilização

1. Arranque a app (como Administrador). `LoadingView` → `StartupSequence` (dependências + backend + frontend).
2. No dashboard, **arraste** um `.exe` ou `.dll`.
3. Escolha:
   - **Análise estática** - submete ao backend e abre o browser nos resultados.
   - **Análise comportamental** - abre `VmAnalysisWindow` com log do pipeline Hyper-V.
4. Opções avançadas (VM): primeira entrada (`05-FirstTimeVmSetup.ps1`), timeout da amostra, esperar saída do processo.

**Relatórios comportamentais:** `D:\PROJETOVM\Reports\` (ou `PROJETOVM_BasePath`).
**Validação sem malware:** [`benign-vm-test`](../benign-vm-test/README.md).

## Credenciais do guest

O PowerShell Direct exige utilizador e password do Windows na VM. Ordem de resolução:

1. Variáveis de ambiente `PROJETOVM_GuestUser` / `PROJETOVM_GuestPassword`
2. Credenciais guardadas na sessão WPF (*Lembrar nesta sessão*)
3. Diálogo `VmGuestCredentialsWindow` (utilizador por defeito: `analyst`)

Em produção: [`docs/production-secrets.md`](../docs/production-secrets.md). **Não** use `PROJETOVM_ALLOW_INSECURE_DEFAULTS` fora de desenvolvimento.

## Variáveis de ambiente

| Variável | Efeito |
|----------|--------|
| `RATANALYZER_API_TOKEN` | Token enviado ao backend (`X-API-Token`); propagado ao uvicorn e ao frontend (`VITE_API_TOKEN`). |
| `RATANALYZER_ENV` / `RATANALYZER_REQUIRE_API_TOKEN` | Modo produção no backend - ver [`docs/production-secrets.md`](../docs/production-secrets.md). |
| `PROJETOVM_BasePath` | Pasta raiz do sandbox (default `D:\PROJETOVM`; lido de `_Config.ps1` se não definido). |
| `PROJETOVM_GuestUser` / `PROJETOVM_GuestPassword` | Credenciais PowerShell Direct na VM guest. |
| `RATANALYZER_ADK_SETUP_SHA256` | Hash obrigatório do instalador ADK transferido para o sandbox. |
| `RATANALYZER_ILSPY_SHA256` | Hash obrigatório do `ilspycmd.exe`. |
| `RATANALYZER_JAVA_EXE_SHA256` | Hash obrigatório do `java.exe` (Temurin 21). |

URLs fixas em `AppConstants.cs`: API `http://localhost:8000`, frontend `http://localhost:8080`.

## Estrutura

Estrutura MVVM estável (refatoração concluída — helpers e bootstrap em subpastas dedicadas):

```
wpf-gui/
├── App.xaml.cs                 # Exige administrador no arranque
├── Bootstrap/                  # Arranque (backend/frontend, dependências, shutdown)
│   ├── StartupSequence.cs
│   ├── ProjectDependencyBootstrap.cs
│   ├── SandboxHostDependencies.cs
│   └── ShutdownManager.cs
├── Helpers/                    # Instalação/validação Ghidra, ILSpy, Java, SHA-256
├── Infrastructure/             # AppConstants, paths PROJETOVM, limpeza local
├── ViewModels/                 # MVVM (MainDashboard, VmAnalysis, …)
├── Views/                      # Dashboard, VmAnalysisWindow, credenciais guest
├── Services/                   # VmSandboxService, StaticAnalysisService, credenciais
└── RatAnalyzer.Desktop.Tests/  # xUnit — paths, integridade, credenciais guest
```

## Segurança

Arquitetura completa: [`docs/SEGURANCA.md`](../docs/SEGURANCA.md) · segredos: [`docs/production-secrets.md`](../docs/production-secrets.md).

- Bind local do backend (`127.0.0.1`) quando arrancado pelo WPF.
- Downloads de ferramentas externas validados por SHA-256 quando `RATANALYZER_*_SHA256` estão definidas.
- Password do guest **não** persistida em disco (apenas sessão em memória, se o utilizador optar).
- VM em rede **Internal** sem internet - ver documentação do sandbox.

## Resolução de problemas

| Sintoma | Ação |
|---------|-------|
| App fecha ao arrancar | Executar **como Administrador** |
| Backend/frontend não arrancam | Python e Node no PATH; portas 8000/8080 livres |
| Análise comportamental falha | [`TROUBLESHOOTING.md`](../scripts/hyperv-sandbox/TROUBLESHOOTING.md) |
| Credenciais guest rejeitadas | `PROJETOVM_GuestPassword` ou diálogo de credenciais |
| Análise estática 401 | `RATANALYZER_API_TOKEN` + propagar ao frontend - [`docs/faq.md`](../docs/faq.md) |
| Primeira VM / runtimes | `05-FirstTimeVmSetup.ps1`, [`offline/runtimes/`](../scripts/hyperv-sandbox/offline/runtimes/README.md) |

## Testes

Testes unitários em `RatAnalyzer.Desktop.Tests/` (xUnit) - helpers, paths do sandbox e credenciais guest:

```powershell
dotnet test wpf-gui/RatAnalyzer.Desktop.Tests/RatAnalyzer.Desktop.Tests.csproj -c Release
```

Solução completa (WPF + vm-agent):

```powershell
dotnet test RatAnalyzer.sln -c Release
```
