using System.Collections.Generic;

namespace WallpaperStudio.Models;

/// <summary>Persisted user settings (mirrors the macOS app's UserDefaults keys).</summary>
public class AppSettings
{
    public string ApiKey { get; set; } = "";
    public int RotateMinutes { get; set; } = 0;        // 0 = off; 15 / 60 / 360 / 1440
    public bool FavoritesOnly { get; set; } = false;
    public bool AllScreens { get; set; } = true;
    public string? Folder { get; set; }                // chosen library folder
    public List<string> Favorites { get; set; } = new();
}

/// <summary>A named set of wallpaper file paths (Library → Collections).</summary>
public class WallpaperCollection
{
    public string Id { get; set; } = System.Guid.NewGuid().ToString();
    public string Name { get; set; } = "";
    public List<string> ImagePaths { get; set; } = new();
}
