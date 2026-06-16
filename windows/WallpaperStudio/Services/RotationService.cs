using System;
using System.Collections.Generic;
using System.Timers;

namespace WallpaperStudio.Services;

/// <summary>Auto-rotates the wallpaper on an interval (port of RotationManager).
/// The UI supplies the candidate pool (favorites-only or whole library).</summary>
public class RotationService : IDisposable
{
    private Timer? _timer;

    /// <summary>Returns the current candidate paths to pick from.</summary>
    public Func<IReadOnlyList<string>>? PoolProvider { get; set; }

    /// <summary>Set the interval in minutes (0 = off). Restarts the timer.</summary>
    public void Configure(int minutes)
    {
        _timer?.Stop();
        _timer?.Dispose();
        _timer = null;
        if (minutes <= 0) return;
        _timer = new Timer(minutes * 60_000.0) { AutoReset = true };
        _timer.Elapsed += (_, _) => ShuffleNow();
        _timer.Start();
    }

    /// <summary>Pick a random wallpaper from the pool and apply it now. Returns the chosen path, if any.</summary>
    public string? ShuffleNow()
    {
        var pool = PoolProvider?.Invoke();
        if (pool is null || pool.Count == 0) return null;
        var path = pool[Random.Shared.Next(pool.Count)];
        WallpaperService.Set(path);
        return path;
    }

    public void Dispose()
    {
        _timer?.Stop();
        _timer?.Dispose();
        _timer = null;
    }
}
