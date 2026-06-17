using System;
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

    /// <summary>Set by the main window: (tab, optional search query) navigates the shell.</summary>
    public Action<string, string?>? Navigate { get; set; }

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
