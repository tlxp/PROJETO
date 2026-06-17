using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace RatAnalyzer.Desktop.Localization;

/// <summary>Strings ligadas ao XAML via {Binding Source={x:Static loc:UiStrings.Instance}, Path=...}</summary>
public sealed class UiStrings : INotifyPropertyChanged
{
    public static UiStrings Instance { get; } = new();

    private UiStrings() => LocalizationManager.LanguageChanged += (_, _) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(string.Empty));

    public event PropertyChangedEventHandler? PropertyChanged;

    public string AppTitle => LocalizationManager.Get(nameof(AppTitle));
    public string LanguageSection => LocalizationManager.Get(nameof(LanguageSection));
    public string LanguageTitle => LocalizationManager.Get(nameof(LanguageTitle));
    public string LanguageSubtitle => LocalizationManager.Get(nameof(LanguageSubtitle));
    public string LanguagePortuguese => LocalizationManager.Get(nameof(LanguagePortuguese));
    public string LanguageEnglish => LocalizationManager.Get(nameof(LanguageEnglish));
    public string LanguageContinue => LocalizationManager.Get(nameof(LanguageContinue));
    public string LanguageCancel => LocalizationManager.Get(nameof(LanguageCancel));
    public string ChangeLanguage => LocalizationManager.Get(nameof(ChangeLanguage));
    public string LoadingSection => LocalizationManager.Get(nameof(LoadingSection));
    public string LoadingTitle => LocalizationManager.Get(nameof(LoadingTitle));
    public string LoadingSubtitle => LocalizationManager.Get(nameof(LoadingSubtitle));
    public string LoadingSpinner => LocalizationManager.Get(nameof(LoadingSpinner));
    public string LoadingLocalHint => LocalizationManager.Get(nameof(LoadingLocalHint));
    public string LoadingLogsTitle => LocalizationManager.Get(nameof(LoadingLogsTitle));
    public string LoadingLogsPorts => LocalizationManager.Get(nameof(LoadingLogsPorts));
    public string LoadingLive => LocalizationManager.Get(nameof(LoadingLive));
    public string DashboardSection => LocalizationManager.Get(nameof(DashboardSection));
    public string DashboardTitle => LocalizationManager.Get(nameof(DashboardTitle));
    public string DashboardSubtitle => LocalizationManager.Get(nameof(DashboardSubtitle));
    public string DashboardDropTitle => LocalizationManager.Get(nameof(DashboardDropTitle));
    public string DashboardDropHint => LocalizationManager.Get(nameof(DashboardDropHint));
    public string DashboardSelectFile => LocalizationManager.Get(nameof(DashboardSelectFile));
    public string DashboardSelectFileTooltip => LocalizationManager.Get(nameof(DashboardSelectFileTooltip));
    public string DashboardChooseAnalysis => LocalizationManager.Get(nameof(DashboardChooseAnalysis));
    public string DashboardChooseHint => LocalizationManager.Get(nameof(DashboardChooseHint));
    public string DashboardStaticAnalysis => LocalizationManager.Get(nameof(DashboardStaticAnalysis));
    public string DashboardVmAnalysis => LocalizationManager.Get(nameof(DashboardVmAnalysis));
    public string DashboardMaintenance => LocalizationManager.Get(nameof(DashboardMaintenance));
    public string DashboardMaintenanceTooltip => LocalizationManager.Get(nameof(DashboardMaintenanceTooltip));
    public string DashboardVmOptions => LocalizationManager.Get(nameof(DashboardVmOptions));
    public string DashboardVmFirstTime => LocalizationManager.Get(nameof(DashboardVmFirstTime));
    public string DashboardVmFirstTimeTooltip => LocalizationManager.Get(nameof(DashboardVmFirstTimeTooltip));
    public string DashboardVmWaitExit => LocalizationManager.Get(nameof(DashboardVmWaitExit));
    public string DashboardVmWaitExitTooltip => LocalizationManager.Get(nameof(DashboardVmWaitExitTooltip));
    public string DashboardVmTimeout => LocalizationManager.Get(nameof(DashboardVmTimeout));
    public string DashboardVmTimeoutTooltip => LocalizationManager.Get(nameof(DashboardVmTimeoutTooltip));
    public string DashboardOpenResults => LocalizationManager.Get(nameof(DashboardOpenResults));
    public string CommonClose => LocalizationManager.Get(nameof(CommonClose));
    public string CommonCancel => LocalizationManager.Get(nameof(CommonCancel));
    public string CommonContinue => LocalizationManager.Get(nameof(CommonContinue));
    public string VmWindowTitle => LocalizationManager.Get(nameof(VmWindowTitle));
    public string VmSection => LocalizationManager.Get(nameof(VmSection));
    public string VmLogTitle => LocalizationManager.Get(nameof(VmLogTitle));
    public string VmLogSubtitle => LocalizationManager.Get(nameof(VmLogSubtitle));
    public string VmOpenLogs => LocalizationManager.Get(nameof(VmOpenLogs));
    public string VmOpenReport => LocalizationManager.Get(nameof(VmOpenReport));
    public string VmCopyRunId => LocalizationManager.Get(nameof(VmCopyRunId));
    public string StorageWindowTitle => LocalizationManager.Get(nameof(StorageWindowTitle));
    public string StorageSection => LocalizationManager.Get(nameof(StorageSection));
    public string StorageTitle => LocalizationManager.Get(nameof(StorageTitle));
    public string StorageSubtitle => LocalizationManager.Get(nameof(StorageSubtitle));
    public string StorageEstimateTitle => LocalizationManager.Get(nameof(StorageEstimateTitle));
    public string StorageRefreshEstimate => LocalizationManager.Get(nameof(StorageRefreshEstimate));
    public string StorageSoftTitle => LocalizationManager.Get(nameof(StorageSoftTitle));
    public string StorageSoftDesc => LocalizationManager.Get(nameof(StorageSoftDesc));
    public string StorageKeepRecent => LocalizationManager.Get(nameof(StorageKeepRecent));
    public string StorageKeepDays => LocalizationManager.Get(nameof(StorageKeepDays));
    public string StorageCleanupNow => LocalizationManager.Get(nameof(StorageCleanupNow));
    public string StorageArchiveTitle => LocalizationManager.Get(nameof(StorageArchiveTitle));
    public string StorageArchiveDesc => LocalizationManager.Get(nameof(StorageArchiveDesc));
    public string StorageArchiveDays => LocalizationManager.Get(nameof(StorageArchiveDays));
    public string StorageArchiveNow => LocalizationManager.Get(nameof(StorageArchiveNow));
    public string StoragePurgeTitle => LocalizationManager.Get(nameof(StoragePurgeTitle));
    public string StoragePurgeDesc => LocalizationManager.Get(nameof(StoragePurgeDesc));
    public string StoragePurgeNow => LocalizationManager.Get(nameof(StoragePurgeNow));
    public string CredentialsWindowTitle => LocalizationManager.Get(nameof(CredentialsWindowTitle));
    public string CredentialsSection => LocalizationManager.Get(nameof(CredentialsSection));
    public string CredentialsTitle => LocalizationManager.Get(nameof(CredentialsTitle));
    public string CredentialsSubtitle => LocalizationManager.Get(nameof(CredentialsSubtitle));
    public string CredentialsUser => LocalizationManager.Get(nameof(CredentialsUser));
    public string CredentialsPassword => LocalizationManager.Get(nameof(CredentialsPassword));
    public string CredentialsRemember => LocalizationManager.Get(nameof(CredentialsRemember));

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
