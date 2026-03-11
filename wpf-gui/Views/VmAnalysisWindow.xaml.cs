using System;
using System.Diagnostics;
using System.IO;
using System.Text;
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
            AppendLine($"[ERRO] {ex.Message}");
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

    private void AppendLine(string line)
    {
        void DoAppend()
        {
            _logBuilder.AppendLine(line);
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
            AppendLine("[ERRO] Pasta scripts/hyperv-sandbox não encontrada. Execute a aplicação a partir da raiz do projeto.");
            return;
        }

        AppendLine($"[*] Pasta dos scripts: {scriptsPath}");
        AppendLine($"[*] Amostra: {_samplePath}");
        AppendLine($"[*] Primeira entrada (instalar software + snapshot): {_runFirstTimeSetup}");
        AppendLine("");

        if (_runFirstTimeSetup)
        {
            StatusText.Text = "Primeira entrada: a instalar software comum na VM (winget) e a criar snapshot...";
            var firstTimeScript = Path.Combine(scriptsPath, "05-FirstTimeVmSetup.ps1");
            if (!File.Exists(firstTimeScript))
            {
                AppendLine($"[ERRO] Script não encontrado: {firstTimeScript}");
                return;
            }
            var exitCode1 = await RunPowerShellScriptAsync(firstTimeScript, arguments: null);
            AppendLine("");
            if (exitCode1 != 0)
            {
                AppendLine("[AVISO] Primeira entrada terminou com erros. A continuar com a execução da amostra.");
            }
        }

        StatusText.Text = "A executar amostra na VM (restore snapshot → run → report → restore snapshot)...";
        var runSampleScript = Path.Combine(scriptsPath, "04-Run-Sample.ps1");
        if (!File.Exists(runSampleScript))
        {
            AppendLine($"[ERRO] Script não encontrado: {runSampleScript}");
            return;
        }

        var sampleArg = $"-SamplePath \"{_samplePath}\"";
        var exitCode2 = await RunPowerShellScriptAsync(runSampleScript, sampleArg);
        AppendLine("");
        if (exitCode2 == 0)
            AppendLine("[*] Análise comportamental concluída. Consulte D:\\PROJETOVM\\Reports\\ para o relatório.");
        else
            AppendLine($"[*] Script terminou com código de saída: {exitCode2}");
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

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
