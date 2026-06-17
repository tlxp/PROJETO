using System.Windows;
using RatAnalyzer.Desktop.Localization;

namespace RatAnalyzer.Desktop.Views;

public partial class VmGuestCredentialsWindow : Window
{
    public VmGuestCredentialsWindow(string defaultUsername)
    {
        InitializeComponent();
        WindowLocalization.BindTitle(this, () => UiStrings.Instance.CredentialsWindowTitle);
        UserTextBox.Text = string.IsNullOrWhiteSpace(defaultUsername) ? "analyst" : defaultUsername;
        Loaded += (_, _) => PasswordBox.Focus();
    }

    public string GuestUser => UserTextBox.Text;

    public string GuestPassword => PasswordBox.Password;

    public bool RememberForSession => RememberCheckBox.IsChecked == true;

    private void Continue_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(UserTextBox.Text))
        {
            MessageBox.Show(this,
                LocalizationManager.Get(LocKeys.MsgCredentialsUserRequired),
                UiStrings.Instance.CredentialsWindowTitle,
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            UserTextBox.Focus();
            return;
        }

        if (string.IsNullOrEmpty(PasswordBox.Password))
        {
            MessageBox.Show(this,
                LocalizationManager.Get(LocKeys.MsgCredentialsPasswordRequired),
                UiStrings.Instance.CredentialsWindowTitle,
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            PasswordBox.Focus();
            return;
        }

        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
