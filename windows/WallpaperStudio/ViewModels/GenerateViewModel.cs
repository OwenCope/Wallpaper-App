using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WallpaperStudio.Services;

namespace WallpaperStudio.ViewModels;

public partial class GenerateViewModel : ViewModelBase
{
    public GradientGenerator.Preset[] Presets => GradientGenerator.Presets;

    [ObservableProperty] private string? _status;

    [RelayCommand]
    private void Apply(GradientGenerator.Preset preset)
    {
        var path = GradientGenerator.Render(preset, 2560, 1440, AppPaths.Generated);
        var ok = WallpaperService.Set(path);
        Status = ok
            ? $"Set “{preset.Name}” as your wallpaper."
            : $"Saved “{preset.Name}”. (Setting the wallpaper works on Windows.)";
    }
}
