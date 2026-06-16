using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace WallpaperStudio.ViewModels;

public partial class MainWindowViewModel : ViewModelBase
{
    public string[] Tabs { get; } = { "Home", "Explore", "Library", "Minecraft" };

    [ObservableProperty] private string _selectedTab = "Home";

    [RelayCommand]
    private void OpenSettings() => SelectedTab = "Settings";
}
