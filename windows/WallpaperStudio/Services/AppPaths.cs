using System;
using System.IO;

namespace WallpaperStudio.Services;

/// <summary>App data locations under %APPDATA%/WallpaperStudio (created on demand).</summary>
public static class AppPaths
{
    public static string Root
    {
        get
        {
            var d = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "WallpaperStudio");
            Directory.CreateDirectory(d);
            return d;
        }
    }

    public static string Downloads => Sub("Downloads");
    public static string Generated => Sub("Generated");

    private static string Sub(string name)
    {
        var p = Path.Combine(Root, name);
        Directory.CreateDirectory(p);
        return p;
    }
}
