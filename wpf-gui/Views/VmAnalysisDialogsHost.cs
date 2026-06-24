// --- Módulo: VmAnalysisDialogsHost.cs ---
using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using RatAnalyzer.Desktop.Bootstrap;
using RatAnalyzer.Desktop.ViewModels;

namespace RatAnalyzer.Desktop.Views;

// --- Implementação WPF de IVmAnalysisDialogs para a janela de análise VM ---
internal sealed class VmAnalysisDialogsHost : IVmAnalysisDialogs
{
    private readonly Window _owner;

    public VmAnalysisDialogsHost(Window owner) => _owner = owner;

    public Task<bool> ConfirmYesNoAsync(string title, string message, bool warningIcon = false)
    {
        return _owner.Dispatcher.InvokeAsync(() =>
            MessageBox.Show(
                _owner,
                message,
                title,
                MessageBoxButton.YesNo,
                warningIcon ? MessageBoxImage.Warning : MessageBoxImage.Question) == MessageBoxResult.Yes).Task;
    }

    public Task<bool> ConfirmAdkInstallAsync()
    {
        return _owner.Dispatcher.InvokeAsync(() =>
            MessageBox.Show(
                _owner,
                "Para automatizar a instalação do Windows na VM, o setup injeta autounattend.xml no ISO. " +
                "Isso exige o Windows ADK — ferramentas de implementação (oscdimg.exe).\r\n\r\n" +
                "Deseja transferir e instalar agora o pacote \"Deployment Tools\" do ADK?\r\n\r\n" +
                "• Será pedida permissão de administrador.\r\n" +
                "• Pode demorar vários minutos e usar vários GB em disco.\r\n" +
                "• Se recusar, o script pode continuar com a ISO original (instalação manual na consola da VM).\r\n\r\n" +
                "Transferências (Microsoft): " + SandboxHostDependencies.AdkSetupDownloadUrl,
                "Instalar Windows ADK (Deployment Tools)?",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) == MessageBoxResult.Yes).Task;
    }

    public void ShowIsoMissingDialog(string? configuredIsoPath)
    {
        _owner.Dispatcher.Invoke(() => ShowWindowsIsoMissingDialog(configuredIsoPath));
    }

    private static void ShowWindowsIsoMissingDialog(string? configuredIsoPath)
    {
        const string downloadPage = "https://www.microsoft.com/pt-pt/software-download/windows10";

        var displayPath = string.IsNullOrWhiteSpace(configuredIsoPath)
            ? "(ver PROJETOVM_WindowsIsoPath em scripts/hyperv-sandbox/_Config.ps1)"
            : configuredIsoPath;

        try
        {
            var folderHint = string.IsNullOrWhiteSpace(configuredIsoPath)
                ? "Configure o caminho completo para o .iso em PROJETOVM_WindowsIsoPath (_Config.ps1) e crie as pastas necessárias."
                : string.IsNullOrWhiteSpace(Path.GetDirectoryName(configuredIsoPath))
                    ? "Garanta que o caminho no _Config.ps1 inclui pasta e nome de ficheiro do .iso."
                    : "Crie esta pasta no disco se ainda não existir:\r\n" + Path.GetDirectoryName(configuredIsoPath);

            var msg =
                "O programa não encontrou a imagem ISO do Windows aqui:\r\n\r\n" +
                displayPath +
                "\r\n\r\n" +
                folderHint +
                "\r\n\r\n" +
                "Requisito: a ISO tem de ser **en-US** (English United States) — mais nada é suportado para instalacao automatica.\r\n\r\n" +
                "Transfira a ISO oficial do Windows 10 através do site da Microsoft " +
                "(ferramenta de criação de suporte ou ficheiro ISO).\r\n" +
                "Depois, copie ou mova o ficheiro .iso para esse caminho exato, " +
                "ou altere scripts\\hyperv-sandbox\\_Config.ps1 (PROJETOVM_WindowsIsoPath).\r\n\r\n" +
                "Site: " + downloadPage +
                "\r\n\r\n" +
                "Deseja abrir a página da Microsoft no navegador agora?";

            if (MessageBox.Show(msg, "ISO do Windows em falta", MessageBoxButton.YesNo, MessageBoxImage.Warning) !=
                MessageBoxResult.Yes)
                return;

            Process.Start(new ProcessStartInfo { FileName = downloadPage, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Não foi possível abrir o navegador. Transfira a ISO manualmente em:\r\n" + downloadPage +
                "\r\n\r\nErro: " + ex.Message,
                "ISO do Windows em falta",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }
}
