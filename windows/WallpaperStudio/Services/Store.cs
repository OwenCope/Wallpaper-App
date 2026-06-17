using System.IO;
using System.Text.Json;

namespace WallpaperStudio.Services;

/// <summary>Tiny JSON persistence for settings/favorites/collections (files under AppPaths.Root).</summary>
public static class Store
{
    private static readonly JsonSerializerOptions Opts = new() { WriteIndented = true };

    public static T Load<T>(string name, T fallback)
    {
        try
        {
            var p = Path.Combine(AppPaths.Root, name);
            if (!File.Exists(p)) return fallback;
            return JsonSerializer.Deserialize<T>(File.ReadAllText(p)) ?? fallback;
        }
        catch { return fallback; }
    }

    public static void Save<T>(string name, T value)
    {
        try { File.WriteAllText(Path.Combine(AppPaths.Root, name), JsonSerializer.Serialize(value, Opts)); }
        catch { /* best effort */ }
    }
}
