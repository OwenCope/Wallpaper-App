using System;
using System.Runtime.CompilerServices;
using WallpaperStudio.Services;

namespace WallpaperStudio.ViewModels;

public class SettingsViewModel : ViewModelBase
{
    public string[] Intervals { get; } = { "Off", "Every 15 minutes", "Every hour", "Every 6 hours", "Every day" };
    private static readonly int[] Mins = { 0, 15, 60, 360, 1440 };

    private static WallpaperStudio.Models.AppSettings S => AppState.Current.Settings;

    public string ApiKey
    {
        get => S.ApiKey;
        set { if (S.ApiKey != value) { S.ApiKey = value; Persist(); Raise(); } }
    }

    public int IntervalIndex
    {
        get { var i = Array.IndexOf(Mins, S.RotateMinutes); return i < 0 ? 0 : i; }
        set
        {
            var m = Mins[Math.Clamp(value, 0, Mins.Length - 1)];
            if (S.RotateMinutes != m) { S.RotateMinutes = m; AppState.Current.Rotation.Configure(m); Persist(); Raise(); }
        }
    }

    public bool FavoritesOnly
    {
        get => S.FavoritesOnly;
        set { if (S.FavoritesOnly != value) { S.FavoritesOnly = value; Persist(); Raise(); } }
    }

    public bool AllScreens
    {
        get => S.AllScreens;
        set { if (S.AllScreens != value) { S.AllScreens = value; Persist(); Raise(); } }
    }

    private void Persist() => AppState.Current.SaveSettings();
    private void Raise([CallerMemberName] string? name = null) => OnPropertyChanged(name);
}
