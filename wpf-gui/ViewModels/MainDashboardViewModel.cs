// --- Módulo: MainDashboardViewModel.cs ---
using System;
using System.Threading.Tasks;
using System.Windows.Input;
using RatAnalyzer.Desktop.Infrastructure;
using RatAnalyzer.Desktop.Localization;
using RatAnalyzer.Desktop.Services;

namespace RatAnalyzer.Desktop.ViewModels;

// --- ViewModel do dashboard: seleção de ficheiro, análise estática e VM ---
public sealed class MainDashboardViewModel : ViewModelBase
{
    private readonly IMainDashboardDialogs _dialogs;
    private readonly StaticAnalysisService _staticAnalysis;

    private string? _lastStaticJobId;
    private string? _lastStaticFilePath;
    private string? _lastVmJobId;
    private string? _lastVmFilePath;

    private bool _showOptions;
    private string? _selectedFilePath;
    private bool _runFirstTimeVmSetup;
    private bool _vmWaitForSampleExit = true;
    private int _vmSampleTimeoutSeconds = 120;
    private bool _isStaticAnalysisBusy;
    private string _staticStatusText = "";
    private bool _showStaticStatus;
    private bool _showStaticProgress;
    private bool _staticProgressIndeterminate;
    private double _staticProgressValue;
    private string _staticJobIdText = "";
    private string _staticJobUrlText = "";
    private bool _showStaticJobDetails;
    private bool _showOpenResults;
    private string? _lastResultsUrl;

    // --- Construtor: regista comandos e serviços ---
    public MainDashboardViewModel(IMainDashboardDialogs dialogs, StaticAnalysisService? staticAnalysis = null)
    {
        _dialogs = dialogs ?? throw new ArgumentNullException(nameof(dialogs));
        _staticAnalysis = staticAnalysis ?? new StaticAnalysisService();

        SelectFileCommand = new RelayCommand(SelectFile);
        RunStaticAnalysisCommand = new RelayCommand(() => _ = RunStaticAnalysisAsync(), () => !IsStaticAnalysisBusy);
        RunDynamicAnalysisCommand = new RelayCommand(RunDynamicAnalysis);
        OpenResultsCommand = new RelayCommand(OpenResults, () => ShowOpenResults);
        OpenStorageMaintenanceCommand = new RelayCommand(OpenStorageMaintenance);
    }

    public bool ShowOptions
    {
        get => _showOptions;
        private set => SetProperty(ref _showOptions, value);
    }

    public bool RunFirstTimeVmSetup
    {
        get => _runFirstTimeVmSetup;
        set => SetProperty(ref _runFirstTimeVmSetup, value);
    }

    public bool VmWaitForSampleExit
    {
        get => _vmWaitForSampleExit;
        set => SetProperty(ref _vmWaitForSampleExit, value);
    }

    public int VmSampleTimeoutSeconds
    {
        get => _vmSampleTimeoutSeconds;
        set => SetProperty(ref _vmSampleTimeoutSeconds, Math.Clamp(value, 5, 7200));
    }

    // --- True enquanto a análise estática decorre (não bloqueia a VM) ---
    public bool IsStaticAnalysisBusy
    {
        get => _isStaticAnalysisBusy;
        private set
        {
            SetProperty(ref _isStaticAnalysisBusy, value);
            InvalidateCommands();
        }
    }

    public string StaticStatusText
    {
        get => _staticStatusText;
        private set => SetProperty(ref _staticStatusText, value);
    }

    public bool ShowStaticStatus
    {
        get => _showStaticStatus;
        private set => SetProperty(ref _showStaticStatus, value);
    }

    public bool ShowStaticProgress
    {
        get => _showStaticProgress;
        private set => SetProperty(ref _showStaticProgress, value);
    }

    public bool StaticProgressIndeterminate
    {
        get => _staticProgressIndeterminate;
        private set => SetProperty(ref _staticProgressIndeterminate, value);
    }

    public double StaticProgressValue
    {
        get => _staticProgressValue;
        private set => SetProperty(ref _staticProgressValue, value);
    }

    public string StaticJobIdText
    {
        get => _staticJobIdText;
        private set => SetProperty(ref _staticJobIdText, value);
    }

    public string StaticJobUrlText
    {
        get => _staticJobUrlText;
        private set => SetProperty(ref _staticJobUrlText, value);
    }

    public bool ShowStaticJobDetails
    {
        get => _showStaticJobDetails;
        private set => SetProperty(ref _showStaticJobDetails, value);
    }

    public bool ShowOpenResults
    {
        get => _showOpenResults;
        private set
        {
            SetProperty(ref _showOpenResults, value);
            InvalidateCommands();
        }
    }

    public ICommand SelectFileCommand { get; }
    public ICommand RunStaticAnalysisCommand { get; }
    public ICommand RunDynamicAnalysisCommand { get; }
    public ICommand OpenResultsCommand { get; }
    public ICommand OpenStorageMaintenanceCommand { get; }

    // --- Reage à seleção ou drop de ficheiro ---
    public void OnFileSelected(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            return;
        _selectedFilePath = path;
        ShowOptions = true;
    }

    private void SelectFile()
    {
        var path = _dialogs.PickAnalysisFile();
        if (!string.IsNullOrWhiteSpace(path))
            OnFileSelected(path);
    }

    // --- Executa análise estática via backend e abre resultados ---
    private async Task RunStaticAnalysisAsync()
    {
        if (string.IsNullOrEmpty(_selectedFilePath))
        {
            _dialogs.ShowInfo(LocalizationManager.Get(LocKeys.MsgNoFile));
            return;
        }

        IsStaticAnalysisBusy = true;
        ResetStaticProgress();
        StaticStatusText = LocalizationManager.Get(LocKeys.MsgStaticPrep);
        ShowStaticStatus = true;
        ShowStaticProgress = true;
        StaticProgressIndeterminate = true;
        StaticProgressValue = 0;
        ShowStaticJobDetails = false;
        ShowOpenResults = false;

        try
        {
            var progress = new Progress<string>(msg => StaticStatusText = msg);
            var progressPct = new Progress<double>(pct =>
            {
                StaticProgressIndeterminate = false;
                StaticProgressValue = Math.Clamp(pct, 0, 100);
            });

            var linkedJobId = ResolveLinkedJobId();

            var jobId = await _staticAnalysis.RunAndPublishAsync(
                _selectedFilePath,
                linkedJobId,
                progress,
                progressPct,
                onJobIdKnown: knownJobId =>
                {
                    // Registar cedo para a VM poder reutilizar o mesmo jobId enquanto a estática decorre.
                    _lastStaticJobId = knownJobId;
                    _lastStaticFilePath = _selectedFilePath;
                    SetResultsUrlForJob(knownJobId);
                }).ConfigureAwait(true);

            _lastStaticJobId = jobId;
            _lastStaticFilePath = _selectedFilePath;

            StaticStatusText = LocalizationManager.Get(LocKeys.MsgStaticDone);
            StaticProgressIndeterminate = false;
            StaticProgressValue = 100;

            SetResultsUrlForJob(jobId);

            // Só abrir automaticamente se a estática foi a primeira análise deste job
            // (evita 2.ª abertura quando a VM já abriu ou quando a VM correr a seguir).
            if (string.IsNullOrWhiteSpace(linkedJobId))
            {
                try
                {
                    _dialogs.OpenBrowserUrl(_lastResultsUrl);
                }
                catch (Exception ex)
                {
                    _dialogs.ShowWarning(
                        LocalizationManager.Format(LocKeys.MsgBrowserFailed, ex.Message),
                        LocalizationManager.Get(LocKeys.AppTitle));
                }
            }
        }
        catch (Exception ex)
        {
            StaticStatusText = LocalizationManager.Get(LocKeys.MsgStaticFailed);
            StaticProgressIndeterminate = false;
            StaticProgressValue = 0;
            _dialogs.ShowError(ex.Message, LocalizationManager.Get(LocKeys.MsgStaticErrorTitle));
        }
        finally
        {
            IsStaticAnalysisBusy = false;
        }
    }

    // --- Abre janela de análise comportamental em VM ---
    private void RunDynamicAnalysis()
    {
        if (string.IsNullOrEmpty(_selectedFilePath))
        {
            _dialogs.ShowInfo(LocalizationManager.Get(LocKeys.MsgNoFile));
            return;
        }

        if (!System.IO.File.Exists(_selectedFilePath))
        {
            _dialogs.ShowWarning(LocalizationManager.Get(LocKeys.MsgFileMissing), LocalizationManager.Get(LocKeys.AppTitle));
            return;
        }

        if (!_dialogs.IsAdministrator())
        {
            _dialogs.ShowAdministratorRequired();
            return;
        }

        var linkedJobId = ResolveLinkedJobId();

        _dialogs.OpenVmAnalysis(
            _selectedFilePath,
            RunFirstTimeVmSetup,
            VmSampleTimeoutSeconds,
            VmWaitForSampleExit,
            linkedJobId,
            onJobIdKnown: id =>
            {
                _lastVmJobId = id;
                _lastVmFilePath = _selectedFilePath;
                SetResultsUrlForJob(id);
            });
    }

    private string? ResolveLinkedJobId()
    {
        if (string.IsNullOrEmpty(_selectedFilePath))
            return null;

        if (string.Equals(_selectedFilePath, _lastVmFilePath, StringComparison.OrdinalIgnoreCase)
            && !string.IsNullOrWhiteSpace(_lastVmJobId))
            return _lastVmJobId;

        if (string.Equals(_selectedFilePath, _lastStaticFilePath, StringComparison.OrdinalIgnoreCase)
            && !string.IsNullOrWhiteSpace(_lastStaticJobId))
            return _lastStaticJobId;

        return null;
    }

    private void OpenResults()
    {
        var jobId = ResolveLinkedJobId();
        var url = !string.IsNullOrWhiteSpace(jobId)
            ? AppConstants.BuildFrontendUrl($"/analysis/{Uri.EscapeDataString(jobId)}")
            : _lastResultsUrl;

        if (string.IsNullOrWhiteSpace(url))
        {
            _dialogs.ShowInfo(LocalizationManager.Get(LocKeys.MsgNoResults));
            return;
        }

        try
        {
            _dialogs.OpenBrowserUrl(url);
        }
        catch (Exception ex)
        {
            _dialogs.ShowWarning(
                LocalizationManager.Format(LocKeys.MsgResultsBrowserFailed, ex.Message),
                LocalizationManager.Get(LocKeys.AppTitle));
        }
    }

    private void OpenStorageMaintenance()
    {
        try
        {
            _dialogs.OpenStorageMaintenance();
        }
        catch (Exception ex)
        {
            _dialogs.ShowWarning(
                LocalizationManager.Format(LocKeys.MsgMaintenanceFailed, ex.Message),
                LocalizationManager.Get(LocKeys.AppTitle));
        }
    }

    private void SetResultsUrlForJob(string jobId)
    {
        _lastResultsUrl = AppConstants.BuildFrontendUrl($"/analysis/{Uri.EscapeDataString(jobId)}");
        StaticJobIdText = LocalizationManager.Format(LocKeys.MsgJobIdFormat, jobId);
        StaticJobUrlText = _lastResultsUrl;
        ShowStaticJobDetails = true;
        ShowOpenResults = true;
    }

    private void ResetStaticProgress()
    {
        StaticStatusText = "";
        ShowStaticStatus = false;
        ShowStaticProgress = false;
        StaticProgressIndeterminate = false;
        StaticProgressValue = 0;
        StaticJobIdText = "";
        StaticJobUrlText = "";
        ShowStaticJobDetails = false;
        ShowOpenResults = false;
    }

    private static void InvalidateCommands() =>
        System.Windows.Input.CommandManager.InvalidateRequerySuggested();
}
