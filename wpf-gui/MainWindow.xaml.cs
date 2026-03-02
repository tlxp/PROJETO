using System;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Animation;
using RatAnalyzer.Desktop.Views;

namespace RatAnalyzer.Desktop;

public partial class MainWindow : Window
{
    private readonly Duration _transitionDuration = TimeSpan.FromMilliseconds(260);

    public MainWindow()
    {
        InitializeComponent();

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

    private void TopBar_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
        {
            DragMove();
        }
    }

    private void MinimizeButton_Click(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState.Minimized;
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}

