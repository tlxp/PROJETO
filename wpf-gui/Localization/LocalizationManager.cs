// --- Módulo: LocalizationManager.cs ---
// Gestor central de idioma pt/en e catálogo de strings.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;
using RatAnalyzer.Desktop.Infrastructure;
namespace RatAnalyzer.Desktop.Localization;
// --- Gestor central de idioma (pt/en) e catálogo de strings ---
public static class LocalizationManager
{
    public const string Portuguese = "pt";
    public const string English = "en";
    private static readonly Dictionary<string, Dictionary<string, string>> Catalog = BuildCatalog();
    public static string LanguageCode { get; private set; } = Portuguese;
    public static bool IsEnglish => LanguageCode == English;
    public static event EventHandler? LanguageChanged;
    // --- Inicializa ---
    public static void Initialize(UserSettings settings)
    {
        if (settings.HasChosenLanguage && !string.IsNullOrWhiteSpace(settings.Language))
            SetLanguage(settings.Language!, persist: false);
        else
            ApplyCulture(Portuguese);
    }
    // --- Define idioma ---
    public static void SetLanguage(string languageCode, bool persist = true)
    {
        languageCode = languageCode == English ? English : Portuguese;
        if (languageCode == LanguageCode && persist)
            return;
        LanguageCode = languageCode;
        ApplyCulture(languageCode);
        if (persist)
            UserSettingsStore.SaveLanguage(languageCode);
        LanguageChanged?.Invoke(null, EventArgs.Empty);
    }
    // --- Obtém ---
    public static string Get(string key) =>
        Catalog.TryGetValue(LanguageCode, out var lang) && lang.TryGetValue(key, out var value)
            ? value
            : Catalog[Portuguese].TryGetValue(key, out var fallback) ? fallback : key;
    // --- Formata ---
    public static string Format(string key, params object[] args) =>
        string.Format(CultureInfo.CurrentCulture, Get(key), args);
    // --- Aplica cultura ---
    private static void ApplyCulture(string languageCode)
    {
        var culture = languageCode == English
            ? CultureInfo.GetCultureInfo("en-US")
            : CultureInfo.GetCultureInfo("pt-PT");
        CultureInfo.CurrentCulture = culture;
        CultureInfo.CurrentUICulture = culture;
        Thread.CurrentThread.CurrentCulture = culture;
        Thread.CurrentThread.CurrentUICulture = culture;
    }
    // --- Obtém Accept idioma ---
    public static string GetAcceptLanguage() =>
        LanguageCode == English ? "en-US,en;q=0.9" : "pt-PT,pt;q=0.9";
    // --- Constrói catálogo ---
    private static Dictionary<string, Dictionary<string, string>> BuildCatalog()
    {
        var pt = Pt();
        var en = En();
        LogCatalog.MergeInto(pt, en);
        return new Dictionary<string, Dictionary<string, string>>
        {
            [Portuguese] = pt,
            [English] = en
        };
    }
    // --- português ---
    private static Dictionary<string, string> Pt() => new()
    {
        [LocKeys.AppTitle] = AppConstants.AppDisplayName,
        [LocKeys.AppSubtitle] = "Análise estática e comportamental de executáveis",
        [LocKeys.LanguageSection] = "IDIOMA",
        [LocKeys.LanguageTitle] = "Escolha o idioma",
        [LocKeys.LanguageSubtitle] = "Pode alterar mais tarde no painel principal.",
        [LocKeys.LanguagePortuguese] = "Português",
        [LocKeys.LanguageEnglish] = "English",
        [LocKeys.LanguageContinue] = "Continuar",
        [LocKeys.LanguageCancel] = "Cancelar",
        [LocKeys.LanguageFooter] = "Ambiente local · análise estática e comportamental",
        [LocKeys.ChangeLanguage] = "Idioma",
        [LocKeys.LoadingSection] = "SANDBOX",
        [LocKeys.LoadingTitle] = "A preparar o ambiente de sandbox",
        [LocKeys.LoadingSubtitle] = "A iniciar backend (porta 8000) e frontend (porta 8080). Ao fechar a aplicação, as portas são libertadas.",
        [LocKeys.LoadingSpinner] = "A arrancar a sandbox em VM...",
        [LocKeys.LoadingLocalHint] = "Tudo corre apenas em local. O dashboard abre automaticamente quando o ambiente estiver pronto.",
        [LocKeys.LoadingLogsTitle] = "Logs de arranque",
        [LocKeys.LoadingLogsPorts] = "Backend · porta 8000  ·  Frontend · porta 8080",
        [LocKeys.LoadingLive] = "AO VIVO",
        [LocKeys.DashboardSection] = "ANÁLISE",
        [LocKeys.DashboardTitle] = "Analisar executáveis suspeitos",
        [LocKeys.DashboardSubtitle] = "Arraste um ficheiro .exe, .dll ou .zip para a sandbox de análise.",
        [LocKeys.DashboardDropTitle] = "Arraste e largue um ficheiro",
        [LocKeys.DashboardDropHint] = ".exe  ·  .dll  ·  .zip  ·  múltiplos samples",
        [LocKeys.DashboardSelectFile] = "Selecionar ficheiro...",
        [LocKeys.DashboardSelectFileTooltip] = "Use este botão se arrastar e largar não funcionar (ex.: ao executar como Administrador).",
        [LocKeys.DashboardChooseAnalysis] = "Escolha o tipo de análise",
        [LocKeys.DashboardChooseHint] = "Executa a análise localmente na pipeline estática ou comportamental da sandbox.",
        [LocKeys.DashboardStaticAnalysis] = "Análise estática",
        [LocKeys.DashboardVmAnalysis] = "Análise comportamental em VM",
        [LocKeys.DashboardMaintenance] = "Manutenção / Limpeza...",
        [LocKeys.DashboardMaintenanceTooltip] = "Limpeza segura de jobs antigos e estimativa de espaço.",
        [LocKeys.DashboardVmOptions] = "Opções da VM",
        [LocKeys.DashboardVmFirstTime] = "Primeira entrada na VM (instalar software comum com winget e criar snapshot)",
        [LocKeys.DashboardVmFirstTimeTooltip] = "Marque se for a primeira vez: instala Chrome, 7zip, VSCode, etc. na VM e cria o snapshot limpo antes de correr a amostra.",
        [LocKeys.DashboardVmWaitExit] = "Aguardar fim natural da amostra (sem matar por timeout)",
        [LocKeys.DashboardVmWaitExitTooltip] = "Se activo, a sandbox espera a amostra terminar sozinha (limite de segurança 2h). Desactive para limitar o tempo activo abaixo.",
        [LocKeys.DashboardVmTimeout] = "Tempo activo máximo (s):",
        [LocKeys.DashboardVmTimeoutTooltip] = "Usado quando a opção acima está desactivada. A amostra é terminada após este tempo se ainda estiver a correr.",
        [LocKeys.DashboardOpenResults] = "Abrir página de resultados",
        [LocKeys.CommonClose] = "Fechar",
        [LocKeys.CommonCancel] = "Cancelar",
        [LocKeys.CommonContinue] = "Continuar",
        [LocKeys.MsgNoFile] = "Nenhum ficheiro selecionado.",
        [LocKeys.MsgFileMissing] = "O ficheiro selecionado já não existe no disco.",
        [LocKeys.MsgNoResults] = "Ainda não existe nenhum job de análise concluído para abrir no navegador.",
        [LocKeys.MsgStaticPrep] = "A preparar ambiente de análise estática...",
        [LocKeys.MsgStaticDone] = "Análise estática concluída. A abrir resultados no navegador...",
        [LocKeys.MsgStaticFailed] = "Falha na análise estática.",
        [LocKeys.MsgStaticErrorTitle] = "Erro na análise estática",
        [LocKeys.MsgBrowserFailed] = "Análise concluída, mas não foi possível abrir o navegador automaticamente.\n\n{0}",
        [LocKeys.MsgResultsBrowserFailed] = "Não foi possível abrir a página de resultados no navegador.\n\n{0}",
        [LocKeys.MsgMaintenanceFailed] = "Não foi possível abrir a janela de manutenção.\n\n{0}",
        [LocKeys.MsgJobIdFormat] = "Job ID: {0}",
        [LocKeys.MsgAdminRequired] = $"Esta operação requer direitos de administrador.\n\nFeche a aplicação e execute-a como Administrador:\n• Clique direito em {AppConstants.ExeFileName} → \"Executar como administrador\"\n• Ou abra o PowerShell como Administrador e execute: dotnet run",
        [LocKeys.MsgAdminRequiredTitle] = "Elevação necessária",
        [LocKeys.MsgStartupFailed] = "Falha no arranque do ambiente.",
        [LocKeys.MsgStartupFailedDetail] = "{0}\n\nPode iniciar manualmente o backend (pasta 'backend') e o frontend (pasta 'frontend').",
        [LocKeys.MsgStartupFailedTitle] = "Erro ao iniciar ambiente",
        [LocKeys.MsgElevationRequired] = $"{AppConstants.AppDisplayName} deve ser executado como Administrador (Hyper-V, scripts PowerShell e outras funcionalidades).\n\nClique direito em {AppConstants.ExeFileName} → \"Executar como administrador\"\nou abra o PowerShell como Administrador e execute: dotnet run",
        [LocKeys.DialogPickFileTitle] = "Selecionar ficheiro para análise",
        [LocKeys.DialogPickFileFilter] = "Executáveis e ficheiros|*.exe;*.dll;*.zip|Todos os ficheiros (*.*)|*.*",
        [LocKeys.VmWindowTitle] = "Análise comportamental em VM",
        [LocKeys.VmSection] = "VM SANDBOX",
        [LocKeys.VmLogTitle] = "Log da análise em tempo real",
        [LocKeys.VmLogSubtitle] = "Comandos e saída da máquina virtual durante a execução.",
        [LocKeys.VmOpenLogs] = "Abrir logs",
        [LocKeys.VmOpenReport] = "Abrir relatório",
        [LocKeys.VmCopyRunId] = "Copiar RunId",
        [LocKeys.StorageWindowTitle] = "Manutenção de armazenamento",
        [LocKeys.StorageSection] = "MANUTENÇÃO",
        [LocKeys.StorageTitle] = "Manutenção / Limpeza",
        [LocKeys.StorageSubtitle] = "Estimativa e limpeza segura de dados temporários e artefatos antigos.",
        [LocKeys.StorageEstimateTitle] = "Espaço atual (estimativa)",
        [LocKeys.StorageRefreshEstimate] = "Recalcular estimativa",
        [LocKeys.StorageSoftTitle] = "Limpeza segura (soft) do histórico de jobs",
        [LocKeys.StorageSoftDesc] = "Remove artefatos antigos em disco (sandbox_jobs) para jobs concluídos/falhados, mantendo a base de dados.",
        [LocKeys.StorageKeepRecent] = "Reter últimos:",
        [LocKeys.StorageKeepDays] = "Reter por dias:",
        [LocKeys.StorageCleanupNow] = "Limpar agora",
        [LocKeys.StorageArchiveTitle] = "Arquivo frio (compressão)",
        [LocKeys.StorageArchiveDesc] = "Zipa out/ em out.zip para jobs antigos e remove a pasta original (recuperação continua possível).",
        [LocKeys.StorageArchiveDays] = "Arquivar com mais de (dias):",
        [LocKeys.StorageArchiveNow] = "Arquivar agora",
        [LocKeys.StoragePurgeTitle] = "Limpeza completa",
        [LocKeys.StoragePurgeDesc] = "Apaga histórico local, amostras, relatórios, descompilados e caches temporários de análise em %LOCALAPPDATA%\\RatAnalyzer (mantém a pasta Ghidra se existir — instalação usada no arranque). Esta ação é irreversível para os dados de análise.",
        [LocKeys.StoragePurgeNow] = "Limpeza completa",
        [LocKeys.StorageStatusLoading] = "A obter estimativa...",
        [LocKeys.CredentialsWindowTitle] = "Conta na VM de análise",
        [LocKeys.CredentialsSection] = "CREDENCIAIS",
        [LocKeys.CredentialsTitle] = "Utilizador e palavra-passe na VM",
        [LocKeys.CredentialsSubtitle] = "Estas credenciais entram na VM via PowerShell Direct. Na primeira instalação são gravadas no autounattend.xml — devem ser as mesmas sempre. Utilizador predefinido: «analyst». Se a VM já foi instalada, use a mesma password (ex.: Analyst123! em dev); credenciais diferentes só funcionam após reinstalar a VM.",
        [LocKeys.CredentialsUser] = "Utilizador na VM",
        [LocKeys.CredentialsPassword] = "Palavra-passe na VM",
        [LocKeys.CredentialsRemember] = "Lembrar nesta sessão da aplicação",
        [LocKeys.MsgCredentialsUserRequired] = "Indique o nome de utilizador que existe (ou vai existir) na VM.",
        [LocKeys.MsgCredentialsPasswordRequired] = "Indique a palavra-passe da conta na VM.",
    };
    // --- inglês ---
    private static Dictionary<string, string> En() => new()
    {
        [LocKeys.AppTitle] = AppConstants.AppDisplayName,
        [LocKeys.AppSubtitle] = "Static and behavioral analysis of executables",
        [LocKeys.LanguageSection] = "LANGUAGE",
        [LocKeys.LanguageTitle] = "Choose your language",
        [LocKeys.LanguageSubtitle] = "You can change this later from the main dashboard.",
        [LocKeys.LanguagePortuguese] = "Português",
        [LocKeys.LanguageEnglish] = "English",
        [LocKeys.LanguageContinue] = "Continue",
        [LocKeys.LanguageCancel] = "Cancel",
        [LocKeys.LanguageFooter] = "Local environment · static and behavioral analysis",
        [LocKeys.ChangeLanguage] = "Language",
        [LocKeys.LoadingSection] = "SANDBOX",
        [LocKeys.LoadingTitle] = "Preparing the sandbox environment",
        [LocKeys.LoadingSubtitle] = "Starting backend (port 8000) and frontend (port 8080). Ports are released when you close the app.",
        [LocKeys.LoadingSpinner] = "Starting the VM sandbox...",
        [LocKeys.LoadingLocalHint] = "Everything runs locally. The dashboard opens automatically when the environment is ready.",
        [LocKeys.LoadingLogsTitle] = "Startup logs",
        [LocKeys.LoadingLogsPorts] = "Backend · port 8000  ·  Frontend · port 8080",
        [LocKeys.LoadingLive] = "LIVE",
        [LocKeys.DashboardSection] = "ANALYSIS",
        [LocKeys.DashboardTitle] = "Analyze suspicious executables",
        [LocKeys.DashboardSubtitle] = "Drag a .exe, .dll or .zip file into the analysis sandbox.",
        [LocKeys.DashboardDropTitle] = "Drag and drop a file",
        [LocKeys.DashboardDropHint] = ".exe  ·  .dll  ·  .zip  ·  multiple samples",
        [LocKeys.DashboardSelectFile] = "Select file...",
        [LocKeys.DashboardSelectFileTooltip] = "Use this button if drag and drop does not work (e.g. when running as Administrator).",
        [LocKeys.DashboardChooseAnalysis] = "Choose analysis type",
        [LocKeys.DashboardChooseHint] = "Runs analysis locally using the static or behavioral sandbox pipeline.",
        [LocKeys.DashboardStaticAnalysis] = "Static analysis",
        [LocKeys.DashboardVmAnalysis] = "Behavioral VM analysis",
        [LocKeys.DashboardMaintenance] = "Maintenance / Cleanup...",
        [LocKeys.DashboardMaintenanceTooltip] = "Safe cleanup of old jobs and disk usage estimate.",
        [LocKeys.DashboardVmOptions] = "VM options",
        [LocKeys.DashboardVmFirstTime] = "First VM boot (install common software with winget and create snapshot)",
        [LocKeys.DashboardVmFirstTimeTooltip] = "Check on first run: installs Chrome, 7zip, VSCode, etc. in the VM and creates a clean snapshot before running the sample.",
        [LocKeys.DashboardVmWaitExit] = "Wait for sample to exit naturally (no timeout kill)",
        [LocKeys.DashboardVmWaitExitTooltip] = "When enabled, the sandbox waits for the sample to finish (2h safety limit). Disable to cap active runtime below.",
        [LocKeys.DashboardVmTimeout] = "Max active time (s):",
        [LocKeys.DashboardVmTimeoutTooltip] = "Used when the option above is disabled. The sample is terminated after this time if still running.",
        [LocKeys.DashboardOpenResults] = "Open results page",
        [LocKeys.CommonClose] = "Close",
        [LocKeys.CommonCancel] = "Cancel",
        [LocKeys.CommonContinue] = "Continue",
        [LocKeys.MsgNoFile] = "No file selected.",
        [LocKeys.MsgFileMissing] = "The selected file no longer exists on disk.",
        [LocKeys.MsgNoResults] = "There is no completed analysis job to open in the browser yet.",
        [LocKeys.MsgStaticPrep] = "Preparing static analysis environment...",
        [LocKeys.MsgStaticDone] = "Static analysis complete. Opening results in the browser...",
        [LocKeys.MsgStaticFailed] = "Static analysis failed.",
        [LocKeys.MsgStaticErrorTitle] = "Static analysis error",
        [LocKeys.MsgBrowserFailed] = "Analysis completed, but the browser could not be opened automatically.\n\n{0}",
        [LocKeys.MsgResultsBrowserFailed] = "Could not open the results page in the browser.\n\n{0}",
        [LocKeys.MsgMaintenanceFailed] = "Could not open the maintenance window.\n\n{0}",
        [LocKeys.MsgJobIdFormat] = "Job ID: {0}",
        [LocKeys.MsgAdminRequired] = $"This operation requires administrator rights.\n\nClose the app and run as Administrator:\n• Right-click {AppConstants.ExeFileName} → \"Run as administrator\"\n• Or open PowerShell as Administrator and run: dotnet run",
        [LocKeys.MsgAdminRequiredTitle] = "Elevation required",
        [LocKeys.MsgStartupFailed] = "Environment startup failed.",
        [LocKeys.MsgStartupFailedDetail] = "{0}\n\nYou can start the backend ('backend' folder) and frontend ('frontend' folder) manually.",
        [LocKeys.MsgStartupFailedTitle] = "Startup error",
        [LocKeys.MsgElevationRequired] = $"{AppConstants.AppDisplayName} must be run as Administrator (Hyper-V, PowerShell scripts and other features).\n\nRight-click {AppConstants.ExeFileName} → \"Run as administrator\"\nor open PowerShell as Administrator and run: dotnet run",
        [LocKeys.DialogPickFileTitle] = "Select file for analysis",
        [LocKeys.DialogPickFileFilter] = "Executables and archives|*.exe;*.dll;*.zip|All files (*.*)|*.*",
        [LocKeys.VmWindowTitle] = "Behavioral VM analysis",
        [LocKeys.VmSection] = "VM SANDBOX",
        [LocKeys.VmLogTitle] = "Real-time analysis log",
        [LocKeys.VmLogSubtitle] = "Commands and VM output during execution.",
        [LocKeys.VmOpenLogs] = "Open logs",
        [LocKeys.VmOpenReport] = "Open report",
        [LocKeys.VmCopyRunId] = "Copy RunId",
        [LocKeys.StorageWindowTitle] = "Storage maintenance",
        [LocKeys.StorageSection] = "MAINTENANCE",
        [LocKeys.StorageTitle] = "Maintenance / Cleanup",
        [LocKeys.StorageSubtitle] = "Estimate and safe cleanup of temporary data and old artifacts.",
        [LocKeys.StorageEstimateTitle] = "Current space (estimate)",
        [LocKeys.StorageRefreshEstimate] = "Recalculate estimate",
        [LocKeys.StorageSoftTitle] = "Safe cleanup (soft) of job history",
        [LocKeys.StorageSoftDesc] = "Removes old on-disk artifacts (sandbox_jobs) for completed/failed jobs while keeping the database.",
        [LocKeys.StorageKeepRecent] = "Keep most recent:",
        [LocKeys.StorageKeepDays] = "Keep for days:",
        [LocKeys.StorageCleanupNow] = "Clean now",
        [LocKeys.StorageArchiveTitle] = "Cold archive (compression)",
        [LocKeys.StorageArchiveDesc] = "Zips out/ to out.zip for old jobs and removes the original folder (recovery remains possible).",
        [LocKeys.StorageArchiveDays] = "Archive older than (days):",
        [LocKeys.StorageArchiveNow] = "Archive now",
        [LocKeys.StoragePurgeTitle] = "Full cleanup",
        [LocKeys.StoragePurgeDesc] = "Deletes local history, samples, reports, decompiled output and temporary analysis caches under %LOCALAPPDATA%\\RatAnalyzer (keeps the Ghidra folder if present — used at startup). This action is irreversible for analysis data.",
        [LocKeys.StoragePurgeNow] = "Full cleanup",
        [LocKeys.StorageStatusLoading] = "Fetching estimate...",
        [LocKeys.CredentialsWindowTitle] = "VM analysis account",
        [LocKeys.CredentialsSection] = "CREDENTIALS",
        [LocKeys.CredentialsTitle] = "VM username and password",
        [LocKeys.CredentialsSubtitle] = "These credentials enter the VM via PowerShell Direct. On first install they are written to autounattend.xml — they must stay the same. Default user: «analyst». If the VM was already installed, use the same password (e.g. Analyst123! in dev); different credentials only work after reinstalling the VM.",
        [LocKeys.CredentialsUser] = "VM username",
        [LocKeys.CredentialsPassword] = "VM password",
        [LocKeys.CredentialsRemember] = "Remember for this app session",
        [LocKeys.MsgCredentialsUserRequired] = "Enter the username that exists (or will exist) on the VM.",
        [LocKeys.MsgCredentialsPasswordRequired] = "Enter the VM account password.",
    };
}
