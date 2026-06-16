# Segredos em produção

O RAT Analyzer usa três segredos principais. **Nunca** ative `ALLOW_INSECURE` em produção.

> Arquitetura de segurança (zonas, auth, uploads): [`SEGURANCA.md`](SEGURANCA.md).

| Segredo | Variável | Componentes |
|---------|----------|-------------|
| Token da API | `RATANALYZER_API_TOKEN` | Backend, WPF, frontend (`VITE_API_TOKEN`) |
| Token do vm-agent | `VM_AGENT_TOKEN` | vm-agent na sandbox, backend (drivers hyperv/proxmox) |
| Password do guest | `PROJETOVM_GuestPassword` | Scripts Hyper-V (PowerShell Direct) |

## Gerar valores seguros

```powershell
.\scripts\generate-production-secrets.ps1
```

Isto cria `secrets/backend.env`, `secrets/frontend.env` e `secrets/sandbox.env` (pasta gitignored). Copie cada ficheiro para `.env` no componente correspondente ou exporte as variáveis no serviço/sistema.

## Modo produção no backend

Com qualquer uma destas variáveis, o backend **recusa arrancar** sem `RATANALYZER_API_TOKEN`:

- `RATANALYZER_ENV=production`
- `RATANALYZER_REQUIRE_SECRETS=1`
- `RATANALYZER_REQUIRE_API_TOKEN=1`

Sem essas flags (dev local em `127.0.0.1`), a API funciona sem token - apenas para desenvolvimento.

## Por componente

### Backend

```powershell
# secrets/backend.env → backend/.env ou variáveis do serviço Windows
$env:RATANALYZER_ENV = "production"
$env:RATANALYZER_API_TOKEN = "<token>"
$env:VM_AGENT_TOKEN = "<mesmo token do vm-agent>"
uvicorn api:app --host 127.0.0.1 --port 8000
```

### Frontend

```env
VITE_API_URL=http://127.0.0.1:8000
VITE_API_TOKEN=<mesmo RATANALYZER_API_TOKEN>
```

Rebuild obrigatório após alterar `.env` (`npm run build`).

### WPF

Defina `RATANALYZER_API_TOKEN` no ambiente do utilizador. O WPF envia `X-API-Token` nos pedidos HTTP e propaga o token ao backend/frontend que arranca automaticamente.

### vm-agent (dentro da VM)

```powershell
$env:VM_AGENT_TOKEN = "<token>"
# NÃO definir VM_AGENT_ALLOW_INSECURE em produção
.\VmAgent.exe --urls http://192.168.100.10:5000
```

### Scripts Hyper-V (host)

```powershell
$env:PROJETOVM_GuestPassword = "<password forte>"
# NÃO definir PROJETOVM_ALLOW_INSECURE_DEFAULTS em produção
.\scripts\hyperv-sandbox\04-Run-Sample.ps1 -SamplePath C:\samples\test.exe
```

## Integridade de dependências (WPF)

O arranque do WPF pode instalar ou validar ferramentas externas. Em produção, pode fixar SHA-256 dos binários em uso:

| Ferramenta | Mecanismo | Variável opcional |
|------------|-----------|-------------------|
| Ghidra | `.sha256` do release GitHub | (automático) |
| ADK (sandbox) | hash do instalador transferido | `RATANALYZER_ADK_SETUP_SHA256` |
| ILSpy (`ilspycmd`) | versão NuGet fixada + hash do shim | `RATANALYZER_ILSPY_SHA256` |
| Java (`java.exe`) | winget Temurin 21 + hash do executável | `RATANALYZER_JAVA_EXE_SHA256` |

O WPF regista sempre o SHA-256 calculado no log de arranque. Se a variável estiver definida, a verificação é **obrigatória** - falha o arranque se não coincidir.

Para obter o hash após uma instalação limpa:

```powershell
Get-FileHash -Algorithm SHA256 "C:\caminho\para\ilspycmd.exe"
Get-FileHash -Algorithm SHA256 "C:\Program Files\Eclipse Adoptium\jdk-21*\bin\java.exe"
```

## Checklist antes de deploy

- [ ] `RATANALYZER_API_TOKEN` definido; `RATANALYZER_ENV=production` ou `RATANALYZER_REQUIRE_API_TOKEN=1`
- [ ] `VITE_API_TOKEN` igual ao token da API (frontend build de produção)
- [ ] `VM_AGENT_TOKEN` igual no backend, vm-agent e `secrets/sandbox.env`
- [ ] `PROJETOVM_GuestPassword` forte; sem `PROJETOVM_ALLOW_INSECURE_DEFAULTS`
- [ ] Pasta `secrets/` e ficheiros `.env` **não** commitados ao Git
- [ ] Backend ligado apenas a `127.0.0.1` ou rede interna com firewall
