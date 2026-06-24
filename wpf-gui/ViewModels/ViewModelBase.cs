// --- Módulo: ViewModelBase.cs ---
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace RatAnalyzer.Desktop.ViewModels;

// --- Base MVVM com notificação de alteração de propriedades ---
public abstract class ViewModelBase : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    // --- Atribui valor e notifica se mudou ---
    protected void SetProperty<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (Equals(field, value))
            return;
        field = value;
        OnPropertyChanged(propertyName);
    }

    // --- Dispara evento PropertyChanged ---
    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
