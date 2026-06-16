using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace WallpaperStudio.Services;

public class WhThumbs
{
    public string Large { get; set; } = "";
    public string Small { get; set; } = "";
}

public class WhPhoto
{
    public string Id { get; set; } = "";
    public string Url { get; set; } = "";
    public string Path { get; set; } = "";          // full-resolution image URL
    public string Resolution { get; set; } = "";
    public WhThumbs Thumbs { get; set; } = new();

    [JsonIgnore] public bool Is4K =>
        Resolution.StartsWith("3840", StringComparison.Ordinal) ||
        Resolution.StartsWith("7680", StringComparison.Ordinal);
}

public class WhMeta
{
    [JsonPropertyName("last_page")] public int LastPage { get; set; }
    [JsonPropertyName("current_page")] public int CurrentPage { get; set; }
}

public class WhResult
{
    public List<WhPhoto> Data { get; set; } = new();
    public WhMeta Meta { get; set; } = new();
}

/// <summary>Wallhaven API client (search + download). Port of the macOS WallhavenService.</summary>
public class WallhavenService
{
    private const string Base = "https://wallhaven.cc/api/v1";
    private static readonly HttpClient Http = new();
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    public async Task<WhResult?> SearchAsync(string query, int page, string sorting, string? apiKey)
    {
        var url = $"{Base}/search?categories=111&purity=100&atleast=1920x1080&sorting={sorting}&page={page}";
        if (!string.IsNullOrWhiteSpace(query)) url += "&q=" + Uri.EscapeDataString(query);
        if (!string.IsNullOrWhiteSpace(apiKey)) url += "&apikey=" + apiKey;
        var body = await Http.GetStringAsync(url);
        return JsonSerializer.Deserialize<WhResult>(body, Json);
    }

    /// <summary>Download the full-res image into a folder; returns the local path.</summary>
    public async Task<string> DownloadAsync(WhPhoto photo, string dir)
    {
        var bytes = await Http.GetByteArrayAsync(photo.Path);
        var ext = System.IO.Path.GetExtension(photo.Path);
        if (string.IsNullOrEmpty(ext)) ext = ".jpg";
        var path = System.IO.Path.Combine(dir, $"wallhaven-{photo.Id}{ext}");
        await File.WriteAllBytesAsync(path, bytes);
        return path;
    }
}
