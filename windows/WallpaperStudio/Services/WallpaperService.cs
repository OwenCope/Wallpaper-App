using System;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace WallpaperStudio.Services;

/// <summary>
/// Sets the Windows desktop wallpaper. Mirrors the macOS WallpaperManager
/// (fill/scale to cover the screen). No-ops off Windows so the app still runs
/// for development on macOS/Linux.
/// </summary>
public static class WallpaperService
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int SystemParametersInfo(int uAction, int uParam, string? lpvParam, int fuWinIni);

    private const int SPI_SETDESKWALLPAPER = 0x0014;
    private const int SPIF_UPDATEINIFILE = 0x01;
    private const int SPIF_SENDWININICHANGE = 0x02;

    /// <summary>Apply an image file as the desktop wallpaper, scaled to fill (crop overflow).</summary>
    public static bool Set(string imagePath)
    {
        if (!OperatingSystem.IsWindows())
            return false; // dev no-op

        try
        {
            SetFillStyle();
            int r = SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, imagePath,
                                         SPIF_UPDATEINIFILE | SPIF_SENDWININICHANGE);
            return r != 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>WallpaperStyle=10 (Fill) / TileWallpaper=0 — cover the screen like macOS.</summary>
    private static void SetFillStyle()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop", writable: true);
        if (key is null) return;
        key.SetValue("WallpaperStyle", "10");
        key.SetValue("TileWallpaper", "0");
    }
}
