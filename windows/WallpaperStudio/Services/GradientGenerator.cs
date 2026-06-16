using System;
using System.IO;
using Avalonia;
using Avalonia.Media;
using Avalonia.Media.Imaging;

namespace WallpaperStudio.Services;

/// <summary>Renders gradient wallpapers to PNG (port of GradientGenerator). Presets mirror the macOS app.</summary>
public static class GradientGenerator
{
    public record Preset(string Id, string Name, string[] Colors, double Angle);

    public static readonly Preset[] Presets =
    {
        new("dusk",     "Dusk",     new[] { "#4F46E5", "#7C3AED", "#DB2777" }, 135),
        new("ocean",    "Ocean",    new[] { "#14B8A6", "#2563EB", "#3730A3" }, 115),
        new("sunrise",  "Sunrise",  new[] { "#FB923C", "#EC4899", "#7C3AED" }, 90),
        new("forest",   "Forest",   new[] { "#22C55E", "#14B8A6", "#04130A" }, 160),
        new("graphite", "Graphite", new[] { "#6B7280", "#0B0B0D" },            135),
        new("candy",    "Candy",    new[] { "#EC4899", "#A855F7", "#3B82F6" }, 45),
    };

    /// <summary>Render a preset at the given pixel size to a PNG and return the file path.</summary>
    public static string Render(Preset p, int width, int height, string dir)
    {
        var brush = new LinearGradientBrush();
        var a = p.Angle * Math.PI / 180.0;
        var dx = Math.Cos(a) * 0.5;
        var dy = Math.Sin(a) * 0.5;
        brush.StartPoint = new RelativePoint(0.5 - dx, 0.5 - dy, RelativeUnit.Relative);
        brush.EndPoint = new RelativePoint(0.5 + dx, 0.5 + dy, RelativeUnit.Relative);
        for (int i = 0; i < p.Colors.Length; i++)
        {
            double offset = p.Colors.Length == 1 ? 0 : (double)i / (p.Colors.Length - 1);
            brush.GradientStops.Add(new GradientStop(Color.Parse(p.Colors[i]), offset));
        }

        var rtb = new RenderTargetBitmap(new PixelSize(width, height), new Vector(96, 96));
        using (var ctx = rtb.CreateDrawingContext())
        {
            ctx.DrawRectangle(brush, null, new Rect(0, 0, width, height));
        }

        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, $"gradient-{p.Id}.png");
        rtb.Save(path);
        return path;
    }
}
