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

        // 0) Modo "não primeira vez": validar pré-requisitos e NÃO reinstalar/configurar nada.
        //    Queremos: ISO já existe (sanity check), VM existe, snapshot limpo existe.
        if (!_runFirstTimeSetup)
        {
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
                AppendLine("[ERRO] ISO do Windows não encontrada. Corrija o caminho em scripts/hyperv-sandbox/_Config.ps1 (PROJETOVM_WindowsIsoPath) ou marque 'Primeira entrada na VM' para criar/reinstalar.", withTimestamp: true);
                await PersistGuiLogAsync();
                return;
            }
            if (!runPreflight.VmExists || !runPreflight.SnapshotExists)
            {
                AppendLine("[ERRO] VM ou snapshot limpo não existem. Marque 'Primeira entrada na VM' para criar/configurar a VM e gerar o snapshot.", withTimestamp: true);
                await PersistGuiLogAsync();
                return;
            }
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
