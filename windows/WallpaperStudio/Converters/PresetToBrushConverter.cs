using System;
using System.Globalization;
using Avalonia;
using Avalonia.Data.Converters;
using Avalonia.Media;
using WallpaperStudio.Services;

namespace WallpaperStudio.Converters;

/// <summary>Turns a gradient Preset into a LinearGradientBrush for the preview tiles.</summary>
public class PresetToBrushConverter : IValueConverter
{
    public static readonly PresetToBrushConverter Instance = new();

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not GradientGenerator.Preset p)
            return Brushes.Transparent;

        var a = p.Angle * Math.PI / 180.0;
        var dx = Math.Cos(a) * 0.5;
        var dy = Math.Sin(a) * 0.5;
        var brush = new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0.5 - dx, 0.5 - dy, RelativeUnit.Relative),
            EndPoint = new RelativePoint(0.5 + dx, 0.5 + dy, RelativeUnit.Relative),
        };
        for (int i = 0; i < p.Colors.Length; i++)
        {
            double offset = p.Colors.Length == 1 ? 0 : (double)i / (p.Colors.Length - 1);
            brush.GradientStops.Add(new GradientStop(Color.Parse(p.Colors[i]), offset));
        }
        return brush;
    }

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
