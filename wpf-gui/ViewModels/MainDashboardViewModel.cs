using System;
using System.Threading.Tasks;
using System.Windows.Input;
using RatAnalyzer.Desktop.Infrastructure;
using RatAnalyzer.Desktop.Services;

namespace RatAnalyzer.Desktop.ViewModels;

public sealed class MainDashboardViewModel : ViewModelBase
{
    private readonly IMainDashboardDialogs _dialogs;
    private readonly StaticAnalysisService _staticAnalysis;

    private bool _showOptions;
    private string? _selectedFilePath;
    private bool _runFirstTimeVmSetup;
    private bool _vmWaitForSampleExit = true;
    private int _vmSampleTimeoutSeconds = 120;
    private bool _isAnalysisBusy;
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

    public MainDashboardViewModel(IMainDashboardDialogs dialogs, StaticAnalysisService? staticAnalysis = null)
    {
        _dialogs = dialogs ?? throw new ArgumentNullException(nameof(dialogs));
        _staticAnalysis = staticAnalysis ?? new StaticAnalysisService();

        SelectFileCommand = new RelayCommand(SelectFile, () => !IsAnalysisBusy);
        RunStaticAnalysisCommand = new RelayCommand(() => _ = RunStaticAnalysisAsync(), () => !IsAnalysisBusy);
        RunDynamicAnalysisCommand = new RelayCommand(RunDynamicAnalysis, () => !IsAnalysisBusy);
        OpenResultsCommand = new RelayCommand(OpenResults, () => ShowOpenResults);
        OpenStorageMaintenanceCommand = new RelayCommand(OpenStorageMaintenance, () => !IsAnalysisBusy);
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

    public bool IsAnalysisBusy
    {
        get => _isAnalysisBusy;
        private set
        {
            SetProperty(ref _isAnalysisBusy, value);
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

    private async Task RunStaticAnalysisAsync()
    {
        if (string.IsNullOrEmpty(_selectedFilePath))
        {
            _dialogs.ShowInfo("Nenhum ficheiro selecionado.");
            return;
        }

        IsAnalysisBusy = true;
        ResetStaticProgress();
        StaticStatusText = "A preparar ambiente de análise estática...";
        ShowStaticStatus = true;
        ShowStaticProgress = true;
        StaticProgressIndeterminate = true;
        StaticProgressValue = 0;
        ShowStaticJobDetails = false;
        ShowOpenResults = false;

        try
        {
            var progress = new Progress<string>(msg => StaticStatusText = msg);
            var jobId = await _staticAnalysis.RunAndPublishAsync(_selectedFilePath, progress).ConfigureAwait(true);

            StaticStatusText = "Análise estática concluída. A abrir resultados no navegador...";
            StaticProgressIndeterminate = false;
            StaticProgressValue = 100;

            _lastResultsUrl = $"{AppConstants.FrontendUrl}/resultados?jobId={Uri.EscapeDataString(jobId)}";
            StaticJobIdText = $"Job ID: {jobId}";
            StaticJobUrlText = _lastResultsUrl;
            ShowStaticJobDetails = true;
            ShowOpenResults = true;

            try
            {
                _dialogs.OpenBrowserUrl(_lastResultsUrl);
            }
            catch (Exception ex)
            {
                _dialogs.ShowWarning(
                    $"Análise concluída, mas não foi possível abrir o navegador automaticamente.\n\n{ex.Message}",
                    "RAT Analyzer");
            }
        }
        catch (Exception ex)
        {
            StaticStatusText = "Falha na análise estática.";
            StaticProgressIndeterminate = false;
            StaticProgressValue = 0;
            _dialogs.ShowError(ex.Message, "Erro na análise estática");
        }
        finally
        {
            IsAnalysisBusy = false;
        }
    }

    private void RunDynamicAnalysis()
    {
        if (string.IsNullOrEmpty(_selectedFilePath))
        {
            _dialogs.ShowInfo("Nenhum ficheiro selecionado.");
            return;
        }

        if (!System.IO.File.Exists(_selectedFilePath))
        {
            _dialogs.ShowWarning("O ficheiro selecionado já não existe no disco.", "RAT Analyzer");
            return;
        }

        if (!_dialogs.IsAdministrator())
        {
            _dialogs.ShowAdministratorRequired();
            return;
        }

        _dialogs.OpenVmAnalysis(_selectedFilePath, RunFirstTimeVmSetup, VmSampleTimeoutSeconds, VmWaitForSampleExit);
    }

    private void OpenResults()
    {
        if (string.IsNullOrWhiteSpace(_lastResultsUrl))
        {
            _dialogs.ShowInfo("Ainda não existe nenhum job de análise concluído para abrir no navegador.");
            return;
        }

        try
        {
            _dialogs.OpenBrowserUrl(_lastResultsUrl);
        }
        catch (Exception ex)
        {
            _dialogs.ShowWarning(
                $"Não foi possível abrir a página de resultados no navegador.\n\n{ex.Message}",
                "RAT Analyzer");
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
                $"Não foi possível abrir a janela de manutenção.\n\n{ex.Message}",
                "RAT Analyzer");
        }
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
