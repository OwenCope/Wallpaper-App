using System.Collections.Generic;
using WallpaperStudio.Models;

namespace WallpaperStudio.Services;

/// <summary>Process-wide app state: settings + shared services. Single instance.</summary>
public sealed class AppState
{
    public static AppState Current { get; } = new();

    public AppSettings Settings { get; }
    public WallhavenService Wallhaven { get; } = new();
    public RotationService Rotation { get; } = new();

    private AppState()
    {
        Settings = Store.Load("settings.json", new AppSettings());
        Rotation.PoolProvider = () => Settings.FavoritesOnly
            ? Settings.Favorites
            : (IReadOnlyList<string>)LibraryService.Images(Settings.Folder);
        Rotation.Configure(Settings.RotateMinutes);
    }

    public void SaveSettings() => Store.Save("settings.json", Settings);
}
