using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using RatAnalyzer.Desktop;

namespace RatAnalyzer.Desktop.Views;

public partial class VmAnalysisWindow : Window
{
    private readonly string _samplePath;
    private readonly bool _runFirstTimeSetup;
    private readonly CancellationTokenSource _cts = new();
    private readonly StringBuilder _logBuilder = new();
    private bool _completed;
    private string? _runId;
    private string? _runDir;

    public VmAnalysisWindow(string samplePath, bool runFirstTimeSetup)
    {
        _samplePath = samplePath ?? throw new ArgumentNullException(nameof(samplePath));
        _runFirstTimeSetup = runFirstTimeSetup;
        InitializeComponent();
        Loaded += OnLoaded;
        Closing += (_, e) =>
        {
            if (!_completed)
            {
                var result = MessageBox.Show(
                    "A análise ainda está a decorrer. Deseja cancelar e fechar?",
                    "Análise em curso",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Question);
                if (result != MessageBoxResult.Yes)
                    e.Cancel = true;
                else
                    _cts.Cancel();
            }
        };
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            await RunAnalysisAsync();
        }
        catch (Exception ex)
        {
            AppendLine($"[ERRO] {ex.Message}", withTimestamp: true);
            StatusText.Text = "Falha.";
            StatusText.Foreground = (Brush)FindResource("DangerBrush");
        }
        finally
        {
            _completed = true;
            ProgressBar.Visibility = Visibility.Collapsed;
            CloseButton.IsEnabled = true;
            if (StatusText.Text == "A iniciar..." || StatusText.Text.Contains("A executar"))
                StatusText.Text = "Concluído.";
        }
    }

    private void AppendLine(string line, bool withTimestamp = false)
    {
        void DoAppend()
        {
            var text = withTimestamp ? $"[{DateTime.Now:HH:mm:ss}] {line}" : line;
            _logBuilder.AppendLine(text);
            TerminalOutput.Text = _logBuilder.ToString();
            if (TerminalScrollViewer != null)
                TerminalScrollViewer.ScrollToVerticalOffset(TerminalScrollViewer.ScrollableHeight);
        }

        if (Dispatcher.CheckAccess())
            DoAppend();
        else
            Dispatcher.BeginInvoke(DispatcherPriority.Normal, DoAppend);
    }

    /// <summary>
    /// Avisa o utilizador a transferir a ISO oficial e a coloca-la no caminho de PROJETOVM_WindowsIsoPath (_Config.ps1).
    /// </summary>
    private static void ShowWindowsIsoMissingDialog(string? configuredIsoPath)
    {
        const string downloadPage = "https://www.microsoft.com/pt-pt/software-download/windows10";

        var displayPath = string.IsNullOrWhiteSpace(configuredIsoPath)
            ? "(ver PROJETOVM_WindowsIsoPath em scripts/hyperv-sandbox/_Config.ps1)"
            : configuredIsoPath;

        try
        {
            string folderHint;
            if (string.IsNullOrWhiteSpace(configuredIsoPath))
            {
                folderHint = "Configure o caminho completo para o .iso em PROJETOVM_WindowsIsoPath (_Config.ps1) e crie as pastas necessárias.";
            }
            else
            {
                var isoDir = Path.GetDirectoryName(configuredIsoPath);
                folderHint = string.IsNullOrWhiteSpace(isoDir)
                    ? "Garanta que o caminho no _Config.ps1 inclui pasta e nome de ficheiro do .iso."
                    : "Crie esta pasta no disco se ainda não existir:\r\n" + isoDir;
            }

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

            var result = MessageBox.Show(
                msg,
                "ISO do Windows em falta",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);

            if (result != MessageBoxResult.Yes)
            {
                return;
            }

            Process.Start(new ProcessStartInfo
            {
                FileName = downloadPage,
                UseShellExecute = true
            });
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

    private static string? FindHyperVScriptsPath()
    {
        var baseDir = AppDomain.CurrentDomain.BaseDirectory;
        var dir = new DirectoryInfo(baseDir);
        for (var i = 0; i < 8 && dir != null; i++)
        {
            var scripts = Path.Combine(dir.FullName, "scripts", "hyperv-sandbox");
            if (Directory.Exists(scripts))
                return scripts;
            dir = dir.Parent;
        }
        return null;
    }

    private async Task RunAnalysisAsync()
    {
        var scriptsPath = FindHyperVScriptsPath();
        if (string.IsNullOrEmpty(scriptsPath) || !Directory.Exists(scriptsPath))
        {
            AppendLine("[ERRO] Pasta scripts/hyperv-sandbox não encontrada. Execute a aplicação a partir da raiz do projeto.", withTimestamp: true);
            return;
        }

        _runId = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        // Tentativa de guardar um bundle em D:\PROJETOVM\Logs\Runs\<runId>
        try
        {
            _runDir = Path.Combine("D:\\PROJETOVM", "Logs", "Runs", _runId);
            Directory.CreateDirectory(_runDir);
            File.WriteAllText(Path.Combine(_runDir, "meta.txt"),
                $"run_id={_runId}{Environment.NewLine}sample_path={_samplePath}{Environment.NewLine}created_at={DateTime.Now:O}{Environment.NewLine}",
                Encoding.UTF8);
        }
        catch
        {
            _runDir = null;
        }

        AppendLine($"[*] Pasta dos scripts: {scriptsPath}", withTimestamp: true);
        AppendLine($"[*] Amostra: {_samplePath}", withTimestamp: true);
        AppendLine($"[*] Primeira entrada (instalar software + snapshot): {_runFirstTimeSetup}", withTimestamp: true);
        if (!string.IsNullOrWhiteSpace(_runId))
            AppendLine($"[*] RunId: {_runId}", withTimestamp: true);
        if (!string.IsNullOrWhiteSpace(_runDir))
            AppendLine($"[*] Pasta de logs: {_runDir}", withTimestamp: true);
        AppendLine("", withTimestamp: true);

        // Preflight comum (_Config.ps1): ISO obrigatório em qualquer fluxo; VM/snapshot só em modo repetido.
        var runPreflight = await GetRunPreflightAsync(scriptsPath);
        if (runPreflight == null)
        {
            AppendLine("[ERRO] Falha no preflight da VM. Não consegui validar VM/snapshot/ISO via PowerShell.", withTimestamp: true);
            await PersistGuiLogAsync();
            return;
        }

        AppendLine($"[*] Preflight: ISO existe: {runPreflight.IsoExists} ({runPreflight.IsoPath})", withTimestamp: true);
        AppendLine($"[*] Preflight: VM existe: {runPreflight.VmExists} ({runPreflight.VmName})", withTimestamp: true);
        AppendLine($"[*] Preflight: Snapshot existe: {runPreflight.SnapshotExists} ({runPreflight.SnapshotName})", withTimestamp: true);
        AppendLine("", withTimestamp: true);

        if (!runPreflight.IsoExists)
        {
            AppendLine("[ERRO] ISO do Windows não encontrada. Transfira a ISO oficial (site Microsoft), coloque no caminho configurado ou edite _Config.ps1.", withTimestamp: true);
            await Dispatcher.InvokeAsync(() => ShowWindowsIsoMissingDialog(runPreflight.IsoPath));
            await PersistGuiLogAsync();
            return;
        }

        // Modo "não primeira vez": também exige VM + snapshot já criados (sem reinstalar).
        if (!_runFirstTimeSetup)
        {
            if (!runPreflight.VmExists || !runPreflight.SnapshotExists)
            {
                AppendLine("[ERRO] VM ou snapshot limpo não existem. Marque 'Primeira entrada na VM' para criar/configurar a VM e gerar o snapshot.", withTimestamp: true);
                await PersistGuiLogAsync();
                return;
            }
        }

        // Primeira entrada: oscdimg (Windows ADK Deployment Tools) para ISO com autounattend
        if (_runFirstTimeSetup)
        {
            AppendLine("[*] A verificar ferramentas do host (Windows ADK / oscdimg)…", withTimestamp: true);
            StatusText.Text = "Dependências do host (ADK)…";
            try
            {
                await SandboxHostDependencies.EnsureOscdimgAsync(
                    msg => AppendLine(msg, true),
                    _cts.Token,
                    async () =>
                    {
                        var op = Dispatcher.InvokeAsync(() =>
                            MessageBox.Show(
                                "Para automatizar a instalação do Windows na VM, o setup injeta autounattend.xml no ISO. " +
                                "Isso exige o Windows ADK — ferramentas de implementação (oscdimg.exe).\r\n\r\n" +
                                "Deseja transferir e instalar agora o pacote \"Deployment Tools\" do ADK?\r\n\r\n" +
                                "• Será pedida permissão de administrador.\r\n" +
                                "• Pode demorar vários minutos e usar vários GB em disco.\r\n" +
                                "• Se recusar, o script pode continuar com a ISO original (instalação manual na consola da VM).\r\n\r\n" +
                                "Transferências (Microsoft): " + SandboxHostDependencies.AdkSetupDownloadUrl,
                                "Instalar Windows ADK (Deployment Tools)?",
                                MessageBoxButton.YesNo,
                                MessageBoxImage.Question) == MessageBoxResult.Yes);
                        return await op.Task.ConfigureAwait(true);
                    });
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

        // 1) Executar setup da sandbox (cria VM, switch, estrutura) se ainda não existir
        var setupScript = Path.Combine(scriptsPath, "01-Setup-MalwareSandbox.ps1");
        if (_runFirstTimeSetup && File.Exists(setupScript))
        {
            // Preflight: se já existir VM/VHD, pedir confirmação na GUI (Read-Host não funciona na app)
            var preflight = await GetSetupPreflightAsync(scriptsPath);
            var setupArgs = (string?)null;
            if (preflight != null && (preflight.VmExists || preflight.VhdExists))
            {
                // IMPORTANTE:
                // Quando "Primeira vez na VM" NÃO está marcado, NUNCA devemos reinstalar/limpar Windows.
                // O setup deve ser idempotente (validar switch/paths/scripts) sem destruir a VM existente.
                if (_runFirstTimeSetup)
                {
                    var msg =
                        "Foram detetados recursos existentes do sandbox Hyper-V:\n\n" +
                        $"- VM: {preflight.VmName} (existe: {preflight.VmExists})\n" +
                        $"- Disco: {preflight.VhdPath} (existe: {preflight.VhdExists})\n\n" +
                        "Pretende ELIMINAR e reinstalar tudo de raiz?";
                    var confirm = MessageBox.Show(
                        msg,
                        "Reinstalar sandbox?",
                        MessageBoxButton.YesNo,
                        MessageBoxImage.Warning);

                    if (confirm == MessageBoxResult.Yes)
                        setupArgs = "-ForceReinstall";
                    else
                        AppendLine("[*] Reinstalação não selecionada. Vou prosseguir sem apagar a VM.", withTimestamp: true);
                }
                else
                {
                    AppendLine("[*] VM/Disco já existem. Como 'Primeira vez na VM' não está marcado, vou manter a VM e NÃO reinstalar.", withTimestamp: true);
                    setupArgs = null;
                }
            }

            AppendLine("[*] A executar setup da sandbox (01-Setup-MalwareSandbox.ps1)...", withTimestamp: true);
            StatusText.Text = "Setup da sandbox Hyper-V...";
            var exitSetup = await RunPowerShellScriptAsync(setupScript, setupArgs);
            AppendLine("", withTimestamp: true);
            if (exitSetup != 0)
            {
                AppendLine("[ERRO] Setup terminou com erros. Parei aqui para evitar passos seguintes inconsistentes. Veja a pasta de logs acima e envie o bundle.", withTimestamp: true);
                AppendLine("", withTimestamp: true);
                await PersistGuiLogAsync();
                return;
            }
        }

        if (_runFirstTimeSetup)
        {
            StatusText.Text = "Primeira entrada: a instalar software comum na VM (winget) e a criar snapshot...";
            var firstTimeScript = Path.Combine(scriptsPath, "05-FirstTimeVmSetup.ps1");
            if (!File.Exists(firstTimeScript))
            {
                AppendLine($"[ERRO] Script não encontrado: {firstTimeScript}", withTimestamp: true);
                return;
            }
            var exitCode1 = await RunPowerShellScriptAsync(firstTimeScript, arguments: null);
            AppendLine("", withTimestamp: true);
            if (exitCode1 != 0)
            {
                AppendLine("[ERRO] Primeira entrada terminou com erros. Parei aqui (não vou correr a amostra) para não mascarar a causa. Envie o bundle da pasta de logs.", withTimestamp: true);
                AppendLine("", withTimestamp: true);
                await PersistGuiLogAsync();
                return;
            }
        }

        StatusText.Text = "A executar amostra na VM (restore snapshot → run → report → restore snapshot)...";
        var runSampleScript = Path.Combine(scriptsPath, "04-Run-Sample.ps1");
        if (!File.Exists(runSampleScript))
        {
            AppendLine($"[ERRO] Script não encontrado: {runSampleScript}", withTimestamp: true);
            return;
        }

        var runIdArg = !string.IsNullOrWhiteSpace(_runId) ? $"-RunId \"{_runId}\"" : "";
        var sampleArg = $"-SamplePath \"{_samplePath}\" {runIdArg}";
        var exitCode2 = await RunPowerShellScriptAsync(runSampleScript, sampleArg);
        AppendLine("", withTimestamp: true);
        if (exitCode2 == 0)
            AppendLine("[*] Análise comportamental concluída. Consulte D:\\PROJETOVM\\Reports\\ para o relatório.", withTimestamp: true);
        else
            AppendLine($"[*] Script terminou com código de saída: {exitCode2}", withTimestamp: true);

        await PersistGuiLogAsync();
    }

    private Task PersistGuiLogAsync()
    {
        return Task.Run(() =>
        {
            try
            {
                if (!string.IsNullOrWhiteSpace(_runDir))
                {
                    File.WriteAllText(Path.Combine(_runDir, "gui_terminal.log"), _logBuilder.ToString(), Encoding.UTF8);
                }
            }
            catch { }
        });
    }

    private Task<int> RunPowerShellScriptAsync(string scriptPath, string? arguments)
    {
        return Task.Run(() =>
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\" {arguments ?? ""}",
                WorkingDirectory = Path.GetDirectoryName(scriptPath) ?? "",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };

            using var process = new Process { StartInfo = psi };
            var outputDone = new ManualResetEventSlim(false);
            var errorDone = new ManualResetEventSlim(false);

            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data != null)
                    AppendLine(e.Data);
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data != null)
                    AppendLine("[stderr] " + e.Data);
            };

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            _cts.Token.Register(() =>
            {
                try { process.Kill(true); } catch { }
            });

            process.WaitForExit();
            return process.ExitCode;
        }, _cts.Token);
    }

    private sealed record SetupPreflight(string VmName, bool VmExists, string VhdPath, bool VhdExists);

    private sealed record RunPreflight(
        string VmName,
        bool VmExists,
        string SnapshotName,
        bool SnapshotExists,
        string IsoPath,
        bool IsoExists
    );

    private Task<RunPreflight?> GetRunPreflightAsync(string scriptsPath)
    {
        return Task.Run(() =>
        {
            try
            {
                var configPath = Path.Combine(scriptsPath, "_Config.ps1");
                if (!File.Exists(configPath))
                    return null;

                // Dot-source da config para usar os mesmos caminhos/nome de VM do projeto.
                var command =
                    "& { " +
                    $"  . \"{configPath}\"; " +
                    "  $vmName = $script:PROJETOVM_VMName; " +
                    "  $snapName = $script:PROJETOVM_SnapshotName; " +
                    "  $iso = $script:PROJETOVM_WindowsIsoPath; " +
                    "  $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue; " +
                    "  $snap = $null; if ($vm) { $snap = Get-VMSnapshot -VMName $vmName -Name $snapName -ErrorAction SilentlyContinue }; " +
                    "  $obj = [pscustomobject]@{ VmName = $vmName; VmExists = [bool]$vm; SnapshotName = $snapName; SnapshotExists = [bool]$snap; IsoPath = $iso; IsoExists = (Test-Path -LiteralPath $iso) }; " +
                    "  $obj | ConvertTo-Json -Compress " +
                    "} ";

                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{command}\"",
                    WorkingDirectory = scriptsPath,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = Encoding.UTF8,
                    StandardErrorEncoding = Encoding.UTF8
                };

                using var process = new Process { StartInfo = psi };
                process.Start();
                var stdout = process.StandardOutput.ReadToEnd();
                process.WaitForExit();
                if (process.ExitCode != 0)
                    return null;

                stdout = stdout?.Trim();
                if (string.IsNullOrWhiteSpace(stdout))
                    return null;

                return JsonSerializer.Deserialize<RunPreflight>(stdout, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
            }
            catch
            {
                return null;
            }
        }, _cts.Token);
    }

    private Task<SetupPreflight?> GetSetupPreflightAsync(string scriptsPath)
    {
        return Task.Run(() =>
        {
            try
            {
                var configPath = Path.Combine(scriptsPath, "_Config.ps1");
                if (!File.Exists(configPath))
                    return null;

                // Dot-source da config para usar os mesmos caminhos/nome de VM do projeto.
                var command =
                    "& { " +
                    $"  . \"{configPath}\"; " +
                    "  $vmName = $script:PROJETOVM_VMName; " +
                    "  $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue; " +
                    "  $vhdPath = Join-Path $script:PROJETOVM_VMPath \"Sandbox.vhdx\"; " +
                    "  $obj = [pscustomobject]@{ VmName = $vmName; VmExists = [bool]$vm; VhdPath = $vhdPath; VhdExists = (Test-Path $vhdPath) }; " +
                    "  $obj | ConvertTo-Json -Compress " +
                    "} ";

                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{command}\"",
                    WorkingDirectory = scriptsPath,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = Encoding.UTF8,
                    StandardErrorEncoding = Encoding.UTF8
                };

                using var process = new Process { StartInfo = psi };
                process.Start();
                var stdout = process.StandardOutput.ReadToEnd();
                process.WaitForExit();
                if (process.ExitCode != 0)
                    return null;

                stdout = stdout?.Trim();
                if (string.IsNullOrWhiteSpace(stdout))
                    return null;

                return JsonSerializer.Deserialize<SetupPreflight>(stdout, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
            }
            catch
            {
                return null;
            }
        }, _cts.Token);
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
