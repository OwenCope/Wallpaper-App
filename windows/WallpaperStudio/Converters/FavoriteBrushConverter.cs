using System;
using System.Globalization;
using Avalonia.Data.Converters;
using Avalonia.Media;

namespace WallpaperStudio.Converters;

/// <summary>true → favorited (red), false → idle (translucent white). For the heart icon.</summary>
public class FavoriteBrushConverter : IValueConverter
{
    private static readonly IBrush On = new SolidColorBrush(Color.Parse("#FF5A7A"));
    private static readonly IBrush Off = new SolidColorBrush(Color.Parse("#88FFFFFF"));

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => (value is true) ? On : Off;

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
