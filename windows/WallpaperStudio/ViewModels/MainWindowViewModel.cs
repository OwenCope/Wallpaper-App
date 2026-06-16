using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace WallpaperStudio.ViewModels;

public partial class MainWindowViewModel : ViewModelBase
{
    public string[] Tabs { get; } = { "Home", "Explore", "Library", "Minecraft" };

    private readonly HomeViewModel _home = new();
    private readonly ExploreViewModel _explore = new();
    private readonly LibraryViewModel _library = new();
    private readonly MinecraftViewModel _minecraft = new();
    private readonly SettingsViewModel _settings = new();

    [ObservableProperty] private string _selectedTab = "Home";
    [ObservableProperty] private ViewModelBase? _currentPage;

    public MainWindowViewModel() => CurrentPage = _home;

    partial void OnSelectedTabChanged(string value) => CurrentPage = value switch
    {
        "Explore" => _explore,
        "Library" => _library,
        "Minecraft" => _minecraft,
        "Settings" => _settings,
        _ => _home,
    };

    // Settings opens directly (it isn't one of the 4 segmented tabs, so we don't touch
    // SelectedTab — that keeps the tab ListBox selection from fighting this).
    [RelayCommand]
    private void OpenSettings() => CurrentPage = _settings;
}
