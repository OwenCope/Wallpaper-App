using System;
using System.IO;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WallpaperStudio.Services;

namespace WallpaperStudio.ViewModels;

public partial class MinecraftViewModel : ViewModelBase
{
    public string[] Poses => SkinRenderService.Poses;
    public string[] Views { get; } = { "Full body", "Bust", "Face" };

    [ObservableProperty] private string _username = "Notch";
    [ObservableProperty] private int _poseIndex;
    [ObservableProperty] private int _viewIndex;
    [ObservableProperty] private Bitmap? _preview;
    [ObservableProperty] private string? _status;
    [ObservableProperty] private bool _busy;

    private byte[]? _lastBytes;

    public MinecraftViewModel() => _ = Render();

    [RelayCommand]
    private async Task Render()
    {
        if (Busy) return;
        Busy = true;
        Status = null;
        try
        {
            var view = ViewIndex switch { 1 => "bust", 2 => "face", _ => "full" };
            var bytes = await SkinRenderService.RenderAsync(Username, Poses[PoseIndex], view);
            if (bytes is null) { Status = "Couldn’t render that username. Check the spelling."; return; }
            _lastBytes = bytes;
            using var ms = new MemoryStream(bytes);
            Preview = new Bitmap(ms);
        }
        catch { Status = "Render failed."; }
        finally { Busy = false; }
    }

    [RelayCommand]
    private void SetWallpaper()
    {
        if (_lastBytes is null) { Status = "Render a character first."; return; }
        try
        {
            using var ms = new MemoryStream(_lastBytes);
            var character = new Bitmap(ms);

            const int W = 2560, H = 1440;
            var rtb = new RenderTargetBitmap(new PixelSize(W, H), new Vector(96, 96));
            using (var ctx = rtb.CreateDrawingContext())
            {
                ctx.FillRectangle(new SolidColorBrush(Color.Parse("#0B0B10")), new Rect(0, 0, W, H));
                // Fit the character to ~80% of the height, centered.
                double ch = H * 0.82;
                double cw = ch * (character.Size.Width / Math.Max(character.Size.Height, 1));
                var dest = new Rect((W - cw) / 2, (H - ch) / 2, cw, ch);
                ctx.DrawImage(character, new Rect(character.Size), dest);
            }

            var path = Path.Combine(AppPaths.Generated, $"minecraft-{Username}.png");
            rtb.Save(path);
            var ok = WallpaperService.Set(path);
            Status = ok ? $"Set {Username} as your wallpaper." : "Saved the image.";
        }
        catch { Status = "Couldn’t set the wallpaper."; }
    }
}
