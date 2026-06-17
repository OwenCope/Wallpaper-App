using System.IO;
using System.Threading.Tasks;
using Avalonia.Media.Imaging;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WallpaperStudio.Services;

namespace WallpaperStudio.ViewModels;

/// <summary>A local library image: downsampled thumbnail, favorite toggle, set as wallpaper.</summary>
public partial class LibItem : ObservableObject
{
    public string Path { get; }

    [ObservableProperty] private Bitmap? _thumb;
    [ObservableProperty] private bool _isFavorite;

    public LibItem(string path)
    {
        Path = path;
        IsFavorite = AppState.Current.Settings.Favorites.Contains(path);
        _ = LoadAsync();
    }

    private async Task LoadAsync()
    {
        try
        {
            var bmp = await Task.Run(() =>
            {
                using var fs = File.OpenRead(Path);
                return Bitmap.DecodeToWidth(fs, 420);
            });
            Thumb = bmp;
        }
        catch { /* unreadable image */ }
    }

    [RelayCommand]
    private void SetWallpaper() => WallpaperService.Set(Path);

    [RelayCommand]
    private void ToggleFavorite()
    {
        var favs = AppState.Current.Settings.Favorites;
        if (favs.Contains(Path)) { favs.Remove(Path); IsFavorite = false; }
        else { favs.Add(Path); IsFavorite = true; }
        AppState.Current.SaveSettings();
    }
}
