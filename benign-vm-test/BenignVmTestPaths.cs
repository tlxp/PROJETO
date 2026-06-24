// --- Módulo: BenignVmTestPaths.cs ---

namespace BenignVmTest;

// --- Caminhos e chaves de registry do smoke test inofensivo ---
public static class BenignVmTestPaths
{
    public const string WorkDir = @"C:\analysis_work";
    public const string MarkerFileName = "benign_test_marker.txt";
    public const string ChildOutputFileName = "child_process.txt";
    public const string RegistryFlagFileName = "registry_flag.txt";

    public const string MarkerPath = WorkDir + @"\" + MarkerFileName;
    public const string ChildOutputPath = WorkDir + @"\" + ChildOutputFileName;
    public const string RegistryFlagPath = WorkDir + @"\" + RegistryFlagFileName;

    public const string RegistryKeyPath = @"Software\RATAnalyzerTest";
    public const string RunOnceKeyPath = @"Software\Microsoft\Windows\CurrentVersion\RunOnce";
    public const string RunOnceValueName = "RATAnalyzerBenignFlag";

    public const string LogPrefix = "[benign-vm-test]";
}
