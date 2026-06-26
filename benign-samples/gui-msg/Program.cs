// --- Módulo: Program.cs (BenignGuiMsg) ---
// Amostra inofensiva: MessageBox sem comportamento malicioso.
namespace BenignGuiMsg;
// --- Ponto de entrada WinForms ---
static class Program
{
    // --- Inicializa runtime e mostra MessageBox inofensivo ---
    [STAThread]
    static int Main()
    {
        ApplicationConfiguration.Initialize();
        MessageBox.Show("BenignGuiMsg: OK", "RAT Analyzer benign sample", MessageBoxButtons.OK, MessageBoxIcon.Information);
        return 0;
    }
}
