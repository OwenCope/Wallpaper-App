using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using Avalonia.Media.Imaging;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WallpaperStudio.Services;

namespace WallpaperStudio.ViewModels;

/// <summary>A single Wallhaven result: lazy-loads its thumbnail, sets/saves the full image.</summary>
public partial class PhotoVM : ObservableObject
{
    private static readonly HttpClient Http = new();

    public WhPhoto Photo { get; }
    public string Resolution => Photo.Resolution;
    public bool Is4K => Photo.Is4K;

    [ObservableProperty] private Bitmap? _thumb;
    [ObservableProperty] private string? _status;

    public PhotoVM(WhPhoto photo) => Photo = photo;

    public async Task LoadThumbAsync()
    {
        try
        {
            var bytes = await Http.GetByteArrayAsync(Photo.Thumbs.Large);
            using var ms = new MemoryStream(bytes);
            Thumb = new Bitmap(ms);
        }
        catch { /* leave placeholder */ }
    }

    [RelayCommand]
    private async Task SetWallpaper()
    {
        Status = "Setting…";
        try
        {
            var path = await AppState.Current.Wallhaven.DownloadAsync(Photo, AppPaths.Downloads);
            var ok = WallpaperService.Set(path);
            Status = ok ? null : "Saved";
        }
        catch { Status = "Failed"; }
    }

    [RelayCommand]
    private async Task Save()
    {
        Status = "Saving…";
        try
        {
            var dir = AppState.Current.Settings.Folder is { Length: > 0 } f && Directory.Exists(f)
                ? f : AppPaths.Downloads;
            await AppState.Current.Wallhaven.DownloadAsync(Photo, dir);
            Status = "Saved";
        }
        catch { Status = "Failed"; }
    }
}
