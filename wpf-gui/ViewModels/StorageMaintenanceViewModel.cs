// --- Módulo: StorageMaintenanceViewModel.cs ---
// ViewModel da janela de manutenção de armazenamento.
using System;
using System.Threading.Tasks;
using System.Windows.Input;
using RatAnalyzer.Desktop.Localization;
using RatAnalyzer.Desktop.Services;
namespace RatAnalyzer.Desktop.ViewModels;
// --- ViewModel da janela de manutenção de armazenamento ---
public sealed class StorageMaintenanceViewModel : ViewModelBase
{
    private readonly IStorageMaintenanceDialogs _dialogs;
    private readonly StorageMaintenanceService _service;
    private string _estimateText = "";
    private string _pathsText = "";
    private string _statusText = LocalizationManager.Get(LocKeys.StorageStatusLoading);
    private string _keepMostRecent = "200";
    private string _retentionDays = "30";
    private string _archiveDays = "30";
    private bool _isBusy;
    public StorageMaintenanceViewModel(
        IStorageMaintenanceDialogs dialogs,
        StorageMaintenanceService? service = null)
    {
        _dialogs = dialogs ?? throw new ArgumentNullException(nameof(dialogs));
        _service = service ?? new StorageMaintenanceService();
        RefreshEstimateCommand = new RelayCommand(() => _ = RefreshEstimateAsync(), () => !IsBusy);
        RunCleanupCommand = new RelayCommand(() => _ = RunCleanupAsync(), () => !IsBusy);
        RunArchiveCommand = new RelayCommand(() => _ = RunArchiveAsync(), () => !IsBusy);
        RunFullPurgeCommand = new RelayCommand(() => _ = RunFullPurgeAsync(), () => !IsBusy);
        CloseCommand = new RelayCommand(() => RequestClose?.Invoke());
    }
    public event Action? RequestClose;
    public string EstimateText
    {
        get => _estimateText;
        private set => SetProperty(ref _estimateText, value);
    }
    public string PathsText
    {
        get => _pathsText;
        private set => SetProperty(ref _pathsText, value);
    }
    public string StatusText
    {
        get => _statusText;
        private set => SetProperty(ref _statusText, value);
    }
    public string KeepMostRecent
    {
        get => _keepMostRecent;
        set => SetProperty(ref _keepMostRecent, value);
    }
    public string RetentionDays
    {
        get => _retentionDays;
        set => SetProperty(ref _retentionDays, value);
    }
    public string ArchiveDays
    {
        get => _archiveDays;
        set => SetProperty(ref _archiveDays, value);
    }
    public bool IsBusy
    {
        get => _isBusy;
        private set
        {
            SetProperty(ref _isBusy, value);
            InvalidateCommands();
        }
    }
    public ICommand RefreshEstimateCommand { get; }
    public ICommand RunCleanupCommand { get; }
    public ICommand RunArchiveCommand { get; }
    public ICommand RunFullPurgeCommand { get; }
    public ICommand CloseCommand { get; }
    // --- Refresh On Load  ---
    public Task RefreshOnLoadAsync() => RefreshEstimateAsync();
    // --- Refresh Estimate  ---
    private async Task RefreshEstimateAsync()
    {
        StatusText = "A obter estimativa...";
        try
        {
            var view = await _service.GetEstimateAsync().ConfigureAwait(true);
            EstimateText = view.EstimateText;
            PathsText = view.PathsText;
            StatusText = "Estimativa atualizada.";
        }
        catch (Exception ex)
        {
            StatusText = "Falha ao obter estimativa: " + ex.Message;
        }
    }
    // --- Executa Cleanup ---
    private async Task RunCleanupAsync()
    {
        if (!StorageMaintenanceService.TryParseInt(KeepMostRecent, 1, 1_000_000, out var keepMostRecent) ||
            !StorageMaintenanceService.TryParseInt(RetentionDays, 0, 36_500, out var retentionDays))
        {
            _dialogs.ShowWarning("Valores inválidos (retenção/dias).");
            return;
        }
        if (!_dialogs.Confirm(
                "Isto remove artefatos antigos em disco para jobs concluídos/falhados (mantém a base de dados), " +
                "apaga pastas temporárias de análise em %TEMP% e remove amostras .exe/.dll guardadas em sandbox_jobs.\n\nContinuar?",
                "Confirmar limpeza"))
            return;
        IsBusy = true;
        StatusText = "A executar limpeza...";
        try
        {
            StatusText = await _service.RunCleanupAsync(retentionDays, keepMostRecent).ConfigureAwait(true);
            await RefreshEstimateAsync().ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            StatusText = "Falha na limpeza: " + ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }
    // --- Executa Archive ---
    private async Task RunArchiveAsync()
    {
        if (!StorageMaintenanceService.TryParseInt(ArchiveDays, 1, 36_500, out var olderThanDays))
        {
            _dialogs.ShowWarning("Valor inválido (dias para arquivo).");
            return;
        }
        if (!_dialogs.Confirm(
                "Isto vai zipar out/ (out.zip) para jobs antigos e remover a pasta out/ original.\n\nContinuar?",
                "Confirmar arquivo frio"))
            return;
        IsBusy = true;
        StatusText = "A arquivar jobs antigos...";
        try
        {
            StatusText = await _service.RunArchiveAsync(olderThanDays).ConfigureAwait(true);
            await RefreshEstimateAsync().ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            StatusText = "Falha no arquivo: " + ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }
    // --- Executa Full Purge ---
    private async Task RunFullPurgeAsync()
    {
        if (!_dialogs.Confirm(
                "Isto vai eliminar todo o histórico local de análises, amostras guardadas, relatórios, " +
                "descompilados, pastas temporárias de análise em %TEMP% e os dados em %LOCALAPPDATA%\\RatAnalyzer " +
                "(mantém a pasta Ghidra, se existir).\n\n" +
                "A ação é irreversível. Continuar?",
                "Confirmar limpeza completa",
                warningIcon: true))
            return;
        IsBusy = true;
        StatusText = "A executar limpeza completa...";
        try
        {
            StatusText = await _service.RunFullPurgeAsync().ConfigureAwait(true);
            await RefreshEstimateAsync().ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            StatusText = "Falha na limpeza completa: " + ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }
    // --- Invalida comandos ---
    private static void InvalidateCommands() =>
        System.Windows.Input.CommandManager.InvalidateRequerySuggested();
}
