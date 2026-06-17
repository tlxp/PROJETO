# Desktop WPF - RAT Analyzer

Aplicação **Windows** (.NET 8 · WPF) - ponto de entrada gráfico do ecossistema: arranque automático do backend e frontend, **análise estática** via API e **análise comportamental** na sandbox Hyper-V (**Caminho B**).

Visão geral: [README principal](../README.md) · sandbox: [`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md) · idiomas: [`docs/i18n.md`](../docs/i18n.md) · índice: [`docs/README.md`](../docs/README.md).

## Índice

- [Funcionalidades](#funcionalidades)
- [Idioma (PT / EN)](#idioma-pt--en)
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
| **Análise estática** | Envia a amostra ao backend FastAPI, obtém `jobId` e abre o browser em `http://localhost:8080/analysis/{jobId}?lang=…`. |
| **Análise comportamental** | Orquestra `scripts/hyperv-sandbox/` (`04-Run-Sample.ps1`), publica o relatório no backend via `POST /api/analysis/upload_dynamic` e abre o frontend no **mesmo `jobId`** se a amostra tiver sido analisada estaticamente antes. |
| **Arranque integrado** | `StartupSequence` verifica ou inicia uvicorn (porta **8000**) e `npm run dev` (porta **8080**). |
| **Bootstrap de dependências** | Instala/valida Python, npm, Ghidra, ILSpy, Java e ADK do sandbox (verificação SHA-256 opcional). |
| **Manutenção de storage** | Janela para estimar/limpar artefatos do backend (`/api/storage/*`). |
| **Credenciais guest** | Diálogo `VmGuestCredentialsWindow` para PowerShell Direct na VM. |
| **Idioma** | Português ou English na UI, logs de arranque e propagação para web/API. |

> A análise dinâmica pelo WPF usa o **pipeline PowerShell Hyper-V** (Caminho B), **não** o driver `hyperv.py` do backend nem o vm-agent HTTP (Caminho A).

### Janelas principais

| Vista | Função |
|-------|--------|
| `LanguageSelectionView` | Escolha PT/EN no primeiro arranque (ou via botão *Idioma*) |
| `LoadingView` | Arranque — `StartupSequence` + bootstrap de dependências (logs ao vivo) |
| `MainDashboardView` | Drop de ficheiros, escolha estática vs comportamental |
| `VmAnalysisWindow` | Log em tempo real do `04-Run-Sample.ps1` |
| `VmGuestCredentialsWindow` | Utilizador/password do guest (sessão ou env) |
| `StorageMaintenanceWindow` | Estimativa, limpeza, arquivo e purge via API |

## Idioma (PT / EN)

1. **Primeiro arranque:** `LanguageSelectionView` — escolha Português ou English.
2. **Persistência:** `%LOCALAPPDATA%\RatAnalyzer\ui-settings.json` (`UserSettingsStore`).
3. **Dashboard:** botão *Idioma* / *Language* reabre o seletor.
4. **Propagação:** ao arrancar backend/frontend define `RATANALYZER_LANG` e `VITE_DEFAULT_LOCALE`; pedidos HTTP incluem `Accept-Language`; URLs do browser incluem `?lang=`.

Detalhes: [`docs/i18n.md`](../docs/i18n.md).

## Requisitos

- **Windows 10/11 Pro** ou Enterprise (ou Server) com **Hyper-V** (análise comportamental).
- **.NET 8 SDK** (compilar) ou runtime (`.exe` publicado).
- **Execução como Administrador** — obrigatória (Hyper-V, scripts PowerShell, firewall).
- **Python 3.10+** e **Node.js 18+** no PATH (arranque automático backend/frontend).
- Sandbox preparado — ver [`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md).

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

1. Arranque a app (como Administrador). Escolha o idioma (primeira vez) → `LoadingView` → `StartupSequence`.
2. No dashboard, **arraste** um `.exe`, `.dll` ou `.zip`.
3. Escolha:
   - **Análise estática** — submete ao backend e abre o browser nos resultados (`/analysis/{jobId}?lang=…`).
   - **Análise comportamental** — executa na VM, envia o relatório para o backend e abre o browser.
4. Opções avançadas (VM): primeira entrada (`05-FirstTimeVmSetup.ps1`), timeout da amostra, esperar saída do processo.

**Relatórios no frontend:** coluna *Relatório* dividida horizontalmente (estático + VM) quando ambos existem.
**Cópia local na VM:** `D:\PROJETOVM\Reports\` (ou `PROJETOVM_BasePath`).
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
| `RATANALYZER_LANG` | Idioma propagado ao backend (`pt` \| `en`). |
| `VITE_DEFAULT_LOCALE` | Idioma inicial do frontend dev server (`pt` \| `en`). |
| `RATANALYZER_ENV` / `RATANALYZER_REQUIRE_API_TOKEN` | Modo produção no backend — ver [`docs/production-secrets.md`](../docs/production-secrets.md). |
| `PROJETOVM_BasePath` | Pasta raiz do sandbox (default `D:\PROJETOVM`; lido de `_Config.ps1` se não definido). |
| `PROJETOVM_GuestUser` / `PROJETOVM_GuestPassword` | Credenciais PowerShell Direct na VM guest. |
| `RATANALYZER_ADK_SETUP_SHA256` | Hash obrigatório do instalador ADK transferido para o sandbox. |
| `RATANALYZER_ILSPY_SHA256` | Hash obrigatório do `ilspycmd.exe`. |
| `RATANALYZER_JAVA_EXE_SHA256` | Hash obrigatório do `java.exe` (Temurin 21). |

URLs em `AppConstants.cs`: API `http://127.0.0.1:8000`, frontend `http://localhost:8080` (com `?lang=` ao abrir resultados).

## Estrutura

Estrutura MVVM com localização e infraestrutura de arranque:

```
wpf-gui/
├── App.xaml / App.xaml.cs      # Design system *Signal*; exige administrador
├── Bootstrap/                  # Arranque (backend/frontend, dependências, shutdown)
├── Helpers/                    # Ghidra, ILSpy, Java, SHA-256
├── Infrastructure/             # AppConstants, ProcessOutputEncoding, UserSettingsStore
├── Localization/               # PT/EN: LocalizationManager, LogCatalog, UiStrings, LocKeys
├── ViewModels/                 # MVVM (MainDashboard, VmAnalysis, Storage, …)
├── Views/                      # Dashboard, Loading, LanguageSelection, VM, credenciais
├── Services/                   # Static/Dynamic analysis, VmSandbox, storage
└── RatAnalyzer.Desktop.Tests/  # xUnit
```

## Segurança

Arquitetura completa: [`docs/SEGURANCA.md`](../docs/SEGURANCA.md) · segredos: [`docs/production-secrets.md`](../docs/production-secrets.md).

- Bind local do backend (`127.0.0.1`) quando arrancado pelo WPF.
- Downloads de ferramentas externas validados por SHA-256 quando `RATANALYZER_*_SHA256` estão definidas.
- Password do guest **não** persistida em disco (apenas sessão em memória, se o utilizador optar).
- VM em rede **Internal** sem internet — ver documentação do sandbox.

## Resolução de problemas

| Sintoma | Ação |
|---------|-------|
| App fecha ao arrancar | Executar **como Administrador** |
| Backend/frontend não arrancam | Python e Node no PATH; portas 8000/8080 livres |
| Caracteres estranhos nos logs | Corrigido via `ProcessOutputEncoding` — atualize para a versão mais recente |
| Web em idioma errado | Reabra resultados pelo WPF (URL com `?lang=`) ou `http://localhost:8080/?lang=en` |
| Análise comportamental falha | [`TROUBLESHOOTING.md`](../scripts/hyperv-sandbox/TROUBLESHOOTING.md) |
| Credenciais guest rejeitadas | `PROJETOVM_GuestPassword` ou diálogo de credenciais |
| Análise estática 401 | `RATANALYZER_API_TOKEN` + propagar ao frontend — [`docs/faq.md`](../docs/faq.md) |
| Primeira VM / runtimes | `05-FirstTimeVmSetup.ps1`, [`offline/runtimes/`](../scripts/hyperv-sandbox/offline/runtimes/README.md) |

## Testes

```powershell
dotnet test wpf-gui/RatAnalyzer.Desktop.Tests/RatAnalyzer.Desktop.Tests.csproj -c Release
dotnet test RatAnalyzer.sln -c Release
```
