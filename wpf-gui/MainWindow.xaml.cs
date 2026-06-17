using System;
using System.Windows;
using System.Windows.Media.Animation;
using RatAnalyzer.Desktop.Infrastructure;
using RatAnalyzer.Desktop.Localization;
using RatAnalyzer.Desktop.Views;

namespace RatAnalyzer.Desktop;

public partial class MainWindow : Window
{
    private readonly Duration _transitionDuration = TimeSpan.FromMilliseconds(260);
    private readonly UserSettings _settings;

    public MainWindow()
    {
        _settings = UserSettingsStore.Load();
        LocalizationManager.Initialize(_settings);

        InitializeComponent();
        Title = UiStrings.Instance.AppTitle;
        LocalizationManager.LanguageChanged += (_, _) => Title = UiStrings.Instance.AppTitle;

        AppNavigation.RequestLanguagePicker = () => ShowLanguageSelection(isFirstLaunch: false);

        if (!_settings.HasChosenLanguage)
            ShowLanguageSelection(isFirstLaunch: true);
        else
            ShowLoading();
    }

    private void ShowLanguageSelection(bool isFirstLaunch)
    {
        var view = new LanguageSelectionView { ShowCancel = !isFirstLaunch };
        view.LanguageConfirmed += (_, _) =>
        {
            if (isFirstLaunch)
                ShowLoading();
            else
                SetContentWithFade(new MainDashboardView(), animateFromZeroOpacity: true);
        };
        view.Cancelled += (_, _) =>
        {
            if (!isFirstLaunch)
                SetContentWithFade(new MainDashboardView(), animateFromZeroOpacity: false);
        };
        SetContentWithFade(view, animateFromZeroOpacity: false);
    }

    private void ShowLoading()
    {
        var loadingView = new LoadingView();
        loadingView.LoadingCompleted += LoadingView_OnLoadingCompleted;
        SetContentWithFade(loadingView, animateFromZeroOpacity: false);
    }

    private void LoadingView_OnLoadingCompleted(object? sender, EventArgs e)
    {
        SetContentWithFade(new MainDashboardView(), animateFromZeroOpacity: true);
    }

    private void SetContentWithFade(object newContent, bool animateFromZeroOpacity)
    {
        ContentHost.Opacity = animateFromZeroOpacity ? 0 : 1;
        ContentHost.Content = newContent;

        var fade = new DoubleAnimation
        {
            From = animateFromZeroOpacity ? 0 : 1,
            To = 1,
            Duration = _transitionDuration,
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };

        ContentHost.BeginAnimation(OpacityProperty, fade);
    }
}
