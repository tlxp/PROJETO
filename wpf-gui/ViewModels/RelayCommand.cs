// --- Módulo: RelayCommand.cs ---
// Implementação simples de ICommand para ligação WPF.
using System;
using System.Windows.Input;



namespace RatAnalyzer.Desktop.ViewModels;



// --- Comando ICommand simples para ligação WPF ---
public sealed class RelayCommand : ICommand
{
    private readonly Action _execute;
    private readonly Func<bool>? _canExecute;



    // --- Construtor com ação e predicado opcional ---
    public RelayCommand(Action execute, Func<bool>? canExecute = null)
    {
        _execute = execute ?? throw new ArgumentNullException(nameof(execute));
        _canExecute = canExecute;
    }



    public event EventHandler? CanExecuteChanged
    {
        add => CommandManager.RequerySuggested += value;
        remove => CommandManager.RequerySuggested -= value;
    }



    // --- Verifica se o comando pode executar ---
    public bool CanExecute(object? parameter) => _canExecute?.Invoke() ?? true;



    // --- Executa o comando ---
    public void Execute(object? parameter) => _execute();
}

