using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using RatAnalyzer.Desktop.Bootstrap;
using RatAnalyzer.Desktop.Infrastructure;
using RatAnalyzer.Desktop.Services;

namespace RatAnalyzer.Desktop.ViewModels;

public sealed class VmAnalysisViewModel : ViewModelBase
{
    private const int MaxLogChars = 400_000;

    private readonly string _samplePath;
    private readonly bool _runFirstTimeSetup;
    private readonly int _sampleTimeoutSeconds;
    private readonly bool _waitForSampleExit;
    private readonly VmGuestCredentials _guestCredentials;
    private readonly IVmAnalysisDialogs _dialogs;
    private readonly DynamicAnalysisService _dynamicAnalysis;
    private readonly Action<string>? _openBrowserUrl;
    private readonly Action<string>? _onJobIdKnown;
    private readonly string? _linkedJobId;
    private string? _activeJobId;
    private readonly CancellationTokenSource _cts = new();
    private readonly StringBuilder _logBuilder = new();
    private readonly Stopwatch _sw = Stopwatch.StartNew();
    private readonly Dispatcher _dispatcher;

    private string _logText = "";
    private string _statusText = "A iniciar...";
    private string _techStatusText = "—";
    private bool _isBusy = true;
    private bool _isStatusError;
    private bool _canClose;
    private bool _canOpenRunFolder;
    private bool _canOpenReport;
    private bool _canCopyRunId;

    private string? _runId;
    private string? _runDir;
    private string? _expectedReportPath;
    private string? _expectedReportJsonPath;
    private string? _reportsDir;

    private DispatcherTimer? _statusTimer;
    private bool _completed;

    public VmAnalysisViewModel(
        string samplePath,
        bool runFirstTimeSetup,
        int sampleTimeoutSeconds,
        bool waitForSampleExit,
        VmGuestCredentials guestCredentials,
        IVmAnalysisDialogs dialogs,
        string? linkedJobId = null,
        Action<string>? openBrowserUrl = null,
        Action<string>? onJobIdKnown = null,
        DynamicAnalysisService? dynamicAnalysis = null)
    {
        _samplePath = samplePath ?? throw new ArgumentNullException(nameof(samplePath));
        _runFirstTimeSetup = runFirstTimeSetup;
        _sampleTimeoutSeconds = Math.Clamp(sampleTimeoutSeconds, 5, 7200);
        _waitForSampleExit = waitForSampleExit;
        _guestCredentials = guestCredentials ?? throw new ArgumentNullException(nameof(guestCredentials));
        _dialogs = dialogs ?? throw new ArgumentNullException(nameof(dialogs));
        _linkedJobId = string.IsNullOrWhiteSpace(linkedJobId) ? null : linkedJobId.Trim();
        _openBrowserUrl = openBrowserUrl;
        _onJobIdKnown = onJobIdKnown;
        _dynamicAnalysis = dynamicAnalysis ?? new DynamicAnalysisService();
        _dispatcher = Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;

        OpenRunFolderCommand = new RelayCommand(OpenRunFolder, () => CanOpenRunFolder);
        OpenReportCommand = new RelayCommand(OpenReport, () => CanOpenReport);
        CopyRunIdCommand = new RelayCommand(CopyRunId, () => CanCopyRunId);
        CloseCommand = new RelayCommand(() => RequestClose?.Invoke(), () => CanClose);
    }

    public event Action? RequestClose;

    public string LogText
    {
        get => _logText;
        private set => SetProperty(ref _logText, value);
    }

    public string StatusText
    {
        get => _statusText;
        private set => SetProperty(ref _statusText, value);
    }

    public string TechStatusText
    {
        get => _techStatusText;
        private set => SetProperty(ref _techStatusText, value);
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set => SetProperty(ref _isBusy, value);
    }

    public bool IsStatusError
    {
        get => _isStatusError;
        private set => SetProperty(ref _isStatusError, value);
    }

    public bool CanClose
    {
        get => _canClose;
        private set => SetProperty(ref _canClose, value);
    }

    public bool CanOpenRunFolder
    {
        get => _canOpenRunFolder;
        private set => SetProperty(ref _canOpenRunFolder, value);
    }

    public bool CanOpenReport
    {
        get => _canOpenReport;
        private set => SetProperty(ref _canOpenReport, value);
    }

    public bool CanCopyRunId
    {
        get => _canCopyRunId;
        private set => SetProperty(ref _canCopyRunId, value);
    }

    public ICommand OpenRunFolderCommand { get; }
    public ICommand OpenReportCommand { get; }
    public ICommand CopyRunIdCommand { get; }
    public ICommand CloseCommand { get; }

    public bool TryCancelClose()
    {
        if (_completed)
            return true;

        var result = MessageBox.Show(
            "A análise ainda está a decorrer. Deseja cancelar e fechar?",
            "Análise em curso",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);

        if (result != MessageBoxResult.Yes)
            return false;

        _cts.Cancel();
        return true;
    }

    public async Task RunAsync()
    {
        try
        {
            StartStatusTimer();
            await RunAnalysisCoreAsync().ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            AppendLine($"[ERRO] {ex.Message}", withTimestamp: true);
            StatusText = "Falha.";
            IsStatusError = true;
        }
        finally
        {
            _completed = true;
            StopStatusTimer();
            IsBusy = false;
            CanClose = true;
            CanOpenRunFolder = !string.IsNullOrWhiteSpace(_runDir);
            CanCopyRunId = !string.IsNullOrWhiteSpace(_runId);
            CanOpenReport = File.Exists(_expectedReportPath ?? "") || File.Exists(_expectedReportJsonPath ?? "");

            if (StatusText == "A iniciar..." || StatusText.Contains("A executar", StringComparison.Ordinal))
                StatusText = "Concluído.";
        }
    }

    private async Task RunAnalysisCoreAsync()
    {
        var scriptsPath = VmSandboxService.FindHyperVScriptsPath();
        if (string.IsNullOrEmpty(scriptsPath) || !Directory.Exists(scriptsPath))
        {
            AppendLine("[ERRO] Pasta scripts/hyperv-sandbox não encontrada. Execute a aplicação a partir da raiz do projeto.", withTimestamp: true);
            return;
        }

        _runId = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        _reportsDir = ProjetoVmPaths.ReportsDir(scriptsPath);

        try
        {
            _runDir = Path.Combine(ProjetoVmPaths.LogsRunsDir(scriptsPath), _runId);
            Directory.CreateDirectory(_runDir);
            await File.WriteAllTextAsync(
                Path.Combine(_runDir, "meta.txt"),
                $"run_id={_runId}{Environment.NewLine}sample_path={_samplePath}{Environment.NewLine}created_at={DateTime.Now:O}{Environment.NewLine}",
                _cts.Token).ConfigureAwait(false);
        }
        catch
        {
            _runDir = null;
        }

        AppendLine($"[*] Pasta dos scripts: {scriptsPath}", withTimestamp: true);
        AppendLine($"[*] Amostra: {_samplePath}", withTimestamp: true);
        AppendLine($"[*] Primeira entrada (instalar software + snapshot): {_runFirstTimeSetup}", withTimestamp: true);
        AppendLine($"[*] Execução da amostra: {(_waitForSampleExit ? "aguardar fim natural" : $"tempo ativo máximo {_sampleTimeoutSeconds}s")}", withTimestamp: true);
        AppendLine($"[*] Conta na VM: {_guestCredentials.Username}", withTimestamp: true);
        if (!string.IsNullOrWhiteSpace(_runId))
            AppendLine($"[*] RunId: {_runId}", withTimestamp: true);
        if (!string.IsNullOrWhiteSpace(_runDir))
            AppendLine($"[*] Pasta de logs: {_runDir}", withTimestamp: true);
        AppendLine("", withTimestamp: true);

        var runPreflight = await VmSandboxService.GetRunPreflightAsync(scriptsPath, _cts.Token, _guestCredentials).ConfigureAwait(true);
        if (runPreflight == null)
        {
            AppendLine("[ERRO] Falha no preflight da VM. Não consegui validar VM/snapshot/ISO via PowerShell (verifique credenciais da VM, Hyper-V e scripts).", withTimestamp: true);
            await PersistGuiLogAsync().ConfigureAwait(false);
            return;
        }

        AppendLine($"[*] Preflight: ISO existe: {runPreflight.IsoExists} ({runPreflight.IsoPath})", withTimestamp: true);
        AppendLine($"[*] Preflight: VM existe: {runPreflight.VmExists} ({runPreflight.VmName})", withTimestamp: true);
        AppendLine($"[*] Preflight: Snapshot existe: {runPreflight.SnapshotExists} ({runPreflight.SnapshotName})", withTimestamp: true);
        AppendLine("", withTimestamp: true);

        if (!runPreflight.IsoExists)
        {
            AppendLine("[ERRO] ISO do Windows não encontrada. Transfira a ISO oficial (site Microsoft), coloque no caminho configurado ou edite _Config.ps1.", withTimestamp: true);
            _dialogs.ShowIsoMissingDialog(runPreflight.IsoPath);
            await PersistGuiLogAsync().ConfigureAwait(false);
            return;
        }

        if (!_runFirstTimeSetup && (!runPreflight.VmExists || !runPreflight.SnapshotExists))
        {
            AppendLine("[ERRO] VM ou snapshot limpo não existem. Marque 'Primeira entrada na VM' para criar/configurar a VM e gerar o snapshot.", withTimestamp: true);
            await PersistGuiLogAsync().ConfigureAwait(false);
            return;
        }

        if (_runFirstTimeSetup)
        {
            AppendLine("[*] A verificar ferramentas do host (Windows ADK / oscdimg)…", withTimestamp: true);
            StatusText = "Dependências do host (ADK)…";
            try
            {
                await SandboxHostDependencies.EnsureOscdimgAsync(
                    msg => AppendLine(msg, true),
                    _cts.Token,
                    () => _dialogs.ConfirmAdkInstallAsync()).ConfigureAwait(true);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                AppendLine($"[AVISO] Verificação ADK: {ex.Message}", withTimestamp: true);
            }

            AppendLine("", withTimestamp: true);
        }

        var setupScript = Path.Combine(scriptsPath, "01-Setup-MalwareSandbox.ps1");
        if (_runFirstTimeSetup && File.Exists(setupScript))
        {
            var preflight = await VmSandboxService.GetSetupPreflightAsync(scriptsPath, _cts.Token, _guestCredentials).ConfigureAwait(true);
            IReadOnlyList<string>? setupArgs = null;
            if (preflight != null && (preflight.VmExists || preflight.VhdExists))
            {
                var msg =
                    "Foram detetados recursos existentes do sandbox Hyper-V:\n\n" +
                    $"- VM: {preflight.VmName} (existe: {preflight.VmExists})\n" +
                    $"- Disco: {preflight.VhdPath} (existe: {preflight.VhdExists})\n\n" +
                    "Pretende ELIMINAR e reinstalar tudo de raiz?";

                if (await _dialogs.ConfirmYesNoAsync("Reinstalar sandbox?", msg, warningIcon: true).ConfigureAwait(true))
                    setupArgs = new[] { "-ForceReinstall" };
                else
                    AppendLine("[*] Reinstalação não selecionada. Vou prosseguir sem apagar a VM.", withTimestamp: true);
            }

            AppendLine("[*] A executar setup da sandbox (01-Setup-MalwareSandbox.ps1)...", withTimestamp: true);
            StatusText = "Setup da sandbox Hyper-V...";
            var exitSetup = await VmSandboxService.RunScriptAsync(
                setupScript, setupArgs, line => AppendLine(line), _cts.Token, _guestCredentials).ConfigureAwait(true);
            AppendLine("", withTimestamp: true);
            if (exitSetup != 0)
            {
                AppendLine("[ERRO] Setup terminou com erros. Parei aqui para evitar passos seguintes inconsistentes. Veja a pasta de logs acima e envie o bundle.", withTimestamp: true);
                AppendLine("", withTimestamp: true);
                await PersistGuiLogAsync().ConfigureAwait(false);
                return;
            }
        }

        if (_runFirstTimeSetup)
        {
            StatusText = "Primeira entrada: a instalar software comum na VM (winget) e a criar snapshot...";
            var firstTimeScript = Path.Combine(scriptsPath, "05-FirstTimeVmSetup.ps1");
            if (!File.Exists(firstTimeScript))
            {
                AppendLine($"[ERRO] Script não encontrado: {firstTimeScript}", withTimestamp: true);
                return;
            }

            var exitCode1 = await VmSandboxService.RunScriptAsync(
                firstTimeScript, null, line => AppendLine(line), _cts.Token, _guestCredentials).ConfigureAwait(true);
            AppendLine("", withTimestamp: true);
            if (exitCode1 != 0)
            {
                AppendLine("[ERRO] Primeira entrada terminou com erros. Parei aqui (não vou correr a amostra) para não mascarar a causa. Envie o bundle da pasta de logs.", withTimestamp: true);
                AppendLine("", withTimestamp: true);
                await PersistGuiLogAsync().ConfigureAwait(false);
                return;
            }
        }

        StatusText = "A executar amostra na VM (restore snapshot → run → report → restore snapshot)...";
        var runSampleScript = Path.Combine(scriptsPath, "04-Run-Sample.ps1");
        if (!File.Exists(runSampleScript))
        {
            AppendLine($"[ERRO] Script não encontrado: {runSampleScript}", withTimestamp: true);
            return;
        }

        if (!string.IsNullOrWhiteSpace(_runId))
        {
            _expectedReportPath = Path.Combine(_reportsDir!, $"analysis_{_runId}.txt");
            _expectedReportJsonPath = Path.Combine(_reportsDir!, $"analysis_{_runId}.json");
        }

        try
        {
            var progress = new Progress<string>(msg => AppendLine($"[*] {msg}", withTimestamp: true));
            _activeJobId = await _dynamicAnalysis.MarkRunningAsync(
                _linkedJobId,
                Path.GetFileName(_samplePath),
                _runId,
                progress,
                _cts.Token).ConfigureAwait(true);
            _onJobIdKnown?.Invoke(_activeJobId);
            AppendLine($"[*] Job associado à análise dinâmica: {_activeJobId}", withTimestamp: true);
        }
        catch (Exception ex)
        {
            AppendLine($"[AVISO] Não foi possível registar a análise dinâmica no backend: {ex.Message}", withTimestamp: true);
            _activeJobId = _linkedJobId;
        }

        var runArgs = new List<string> { "-SamplePath", _samplePath };
        if (!string.IsNullOrWhiteSpace(_runId))
            runArgs.AddRange(new[] { "-RunId", _runId });
        runArgs.AddRange(new[] { "-TimeoutSeconds", _sampleTimeoutSeconds.ToString() });
        if (!_waitForSampleExit)
            runArgs.Add("-SampleTimeoutKill");

        var exitCode2 = await VmSandboxService.RunScriptAsync(
            runSampleScript, runArgs, line => AppendLine(line), _cts.Token, _guestCredentials).ConfigureAwait(true);
        AppendLine("", withTimestamp: true);

        var runJsonPath = !string.IsNullOrWhiteSpace(_runId) && !string.IsNullOrWhiteSpace(_runDir)
            ? Path.Combine(_runDir, $"run_{_runId}.json")
            : null;
        var reportReady = !string.IsNullOrWhiteSpace(_expectedReportPath) && File.Exists(_expectedReportPath);
        var runStatus = VmSandboxService.TryReadRunStatus(runJsonPath);

        if (exitCode2 == 0 && reportReady)
            AppendLine($"[*] Análise comportamental concluída. Consulte {_reportsDir} para o relatório.", withTimestamp: true);
        else if (reportReady)
            AppendLine("[AVISO] O script terminou com erros, mas o relatório foi gerado.", withTimestamp: true);
        else if (exitCode2 == 0)
            AppendLine("[AVISO] O script terminou sem erros, mas o relatório não foi encontrado no host.", withTimestamp: true);
        else
            AppendLine($"[ERRO] A análise na VM falhou (código de saída: {exitCode2}).", withTimestamp: true);

        if (!string.IsNullOrWhiteSpace(runStatus) && !string.Equals(runStatus, "ok", StringComparison.OrdinalIgnoreCase))
            AppendLine($"[*] Estado registado no run: {runStatus}", withTimestamp: true);

        if (!string.IsNullOrWhiteSpace(_expectedReportPath))
            AppendLine($"[*] Relatório esperado: {_expectedReportPath}", withTimestamp: true);
        if (!string.IsNullOrWhiteSpace(_expectedReportJsonPath))
            AppendLine($"[*] JSON esperado: {_expectedReportJsonPath}", withTimestamp: true);

        if (reportReady && !string.IsNullOrWhiteSpace(_expectedReportPath))
            await TryPublishDynamicReportAsync().ConfigureAwait(true);

        await PersistGuiLogAsync().ConfigureAwait(false);
    }

    private async Task TryPublishDynamicReportAsync()
    {
        if (string.IsNullOrWhiteSpace(_expectedReportPath) || !File.Exists(_expectedReportPath))
            return;

        try
        {
            StatusText = "A enviar relatório para o frontend...";
            var progress = new Progress<string>(msg => AppendLine($"[*] {msg}", withTimestamp: true));
            var jobId = await _dynamicAnalysis.PublishReportAsync(
                _activeJobId ?? _linkedJobId,
                _expectedReportPath,
                Path.GetFileName(_samplePath),
                _runId,
                progress,
                _cts.Token).ConfigureAwait(true);

            _activeJobId = jobId;
            var resultsUrl = AppConstants.BuildFrontendUrl($"/analysis/{Uri.EscapeDataString(jobId)}");
            AppendLine($"[*] Relatório publicado no backend. URL: {resultsUrl}", withTimestamp: true);
            StatusText = "Concluído — relatório disponível no frontend.";

            try
            {
                _openBrowserUrl?.Invoke(resultsUrl);
            }
            catch (Exception ex)
            {
                AppendLine($"[AVISO] Não foi possível abrir o navegador automaticamente: {ex.Message}", withTimestamp: true);
            }
        }
        catch (Exception ex)
        {
            AppendLine($"[AVISO] Falha ao publicar relatório no backend: {ex.Message}", withTimestamp: true);
        }
    }

    private void AppendLine(string line, bool withTimestamp = false)
    {
        void DoAppend()
        {
            var lineText = ProcessOutputEncoding.NormalizeForDisplay(line);
            var text = withTimestamp ? $"[{DateTime.Now:HH:mm:ss}] {lineText}" : lineText;
            _logBuilder.AppendLine(text);
            if (_logBuilder.Length > MaxLogChars)
            {
                _logBuilder.Remove(0, Math.Min(_logBuilder.Length, 60_000));
                _logBuilder.Insert(0, "[log truncado: mantendo o final do output]\r\n");
            }

            LogText = _logBuilder.ToString();
        }

        if (_dispatcher.CheckAccess())
            DoAppend();
        else
            _dispatcher.BeginInvoke(DispatcherPriority.Normal, DoAppend);
    }

    private Task PersistGuiLogAsync()
    {
        return Task.Run(() =>
        {
            try
            {
                if (!string.IsNullOrWhiteSpace(_runDir))
                    File.WriteAllText(Path.Combine(_runDir, "gui_terminal.log"), _logBuilder.ToString(), Encoding.UTF8);
            }
            catch { /* ignorar */ }
        });
    }

    private void StartStatusTimer()
    {
        _statusTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _statusTimer.Tick += (_, _) =>
        {
            var run = string.IsNullOrWhiteSpace(_runId) ? "-" : _runId;
            var phase = ExtractLastPhase(_logBuilder.ToString());
            TechStatusText = $"RunId={run} | phase={phase} | elapsed={_sw.Elapsed:hh\\:mm\\:ss}";
        };
        _statusTimer.Start();
    }

    private void StopStatusTimer()
    {
        try
        {
            _statusTimer?.Stop();
            _statusTimer = null;
        }
        catch { /* ignorar */ }
    }

    private static string ExtractLastPhase(string logText)
    {
        if (string.IsNullOrEmpty(logText))
            return "-";

        var lines = logText.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
        for (var i = lines.Length - 1; i >= 0; i--)
        {
            var l = lines[i];
            if (l.Contains("[2/7]") || l.Contains("[3/7]") || l.Contains("[4/7]") ||
                l.Contains("[5/7]") || l.Contains("[6/7]") || l.Contains("[7/7]") || l.Contains("[8/8]"))
                return l.Trim();
            if (l.Contains("A executar amostra") || l.Contains("Setup da sandbox") || l.Contains("Primeira entrada"))
                return l.Trim();
        }

        return "-";
    }

    private void OpenRunFolder()
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(_runDir) && Directory.Exists(_runDir))
                Process.Start(new ProcessStartInfo { FileName = _runDir, UseShellExecute = true });
        }
        catch { /* ignorar */ }
    }

    private void OpenReport()
    {
        try
        {
            var p = File.Exists(_expectedReportPath ?? "") ? _expectedReportPath : _expectedReportJsonPath;
            if (!string.IsNullOrWhiteSpace(p) && File.Exists(p))
                Process.Start(new ProcessStartInfo { FileName = p, UseShellExecute = true });
            else if (!string.IsNullOrWhiteSpace(_reportsDir) && Directory.Exists(_reportsDir))
                Process.Start(new ProcessStartInfo { FileName = _reportsDir, UseShellExecute = true });
        }
        catch { /* ignorar */ }
    }

    private void CopyRunId()
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(_runId))
                Clipboard.SetText(_runId);
        }
        catch { /* ignorar */ }
    }
}
