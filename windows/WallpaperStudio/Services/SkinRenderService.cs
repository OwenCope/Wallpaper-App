using System;
using System.Net.Http;
using System.Threading.Tasks;

namespace WallpaperStudio.Services;

/// <summary>Fetches a posed 2D character render (Starlight Skins, mc-heads fallback). Port of the macOS SkinRenderService.</summary>
public static class SkinRenderService
{
    private static readonly HttpClient Http = new();

    public static readonly string[] Poses =
    {
        "default", "isometric", "marching", "walking", "crouching", "pointing", "lunging",
        "cheering", "archer", "relaxing", "trudging", "kicking", "reading", "mojavatar", "ultimate"
    };

    public static readonly string[] Views = { "full", "bust", "face" };

    public static async Task<byte[]?> RenderAsync(string username, string pose, string view)
    {
        username = username.Trim();
        if (username.Length == 0) return null;

        // 1) Starlight in the chosen pose, 2) Starlight default, 3) mc-heads body.
        return await Try($"https://starlightskins.lunareclipse.studio/render/{pose}/{Uri.EscapeDataString(username)}/{view}")
            ?? await Try($"https://starlightskins.lunareclipse.studio/render/default/{Uri.EscapeDataString(username)}/{view}")
            ?? await Try($"https://mc-heads.net/body/{Uri.EscapeDataString(username)}/512");
    }

    private static async Task<byte[]?> Try(string url)
    {
        try
        {
            var r = await Http.GetAsync(url);
            if (r.IsSuccessStatusCode) return await r.Content.ReadAsByteArrayAsync();
        }
        catch { /* try next */ }
        return null;
    }
}
