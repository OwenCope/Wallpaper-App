using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using WallpaperStudio.Models;

namespace WallpaperStudio.Services;

/// <summary>Local image library: folder scan, favorites, and collections (port of LibraryStore + CollectionStore).</summary>
public static class LibraryService
{
    private static readonly string[] Exts =
        { ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".tiff", ".heic", ".heif" };

    /// <summary>Image files in a folder (non-recursive), sorted by name.</summary>
    public static List<string> Images(string? folder)
    {
        if (string.IsNullOrEmpty(folder) || !Directory.Exists(folder)) return new();
        try
        {
            return Directory.EnumerateFiles(folder)
                .Where(f => Exts.Contains(Path.GetExtension(f).ToLowerInvariant()))
                .OrderBy(f => f, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }
        catch { return new(); }
    }

    // --- Collections (persisted to collections.json) ---
    private const string CollectionsFile = "collections.json";

    public static List<WallpaperCollection> LoadCollections() =>
        Store.Load(CollectionsFile, new List<WallpaperCollection>());

    public static void SaveCollections(List<WallpaperCollection> collections) =>
        Store.Save(CollectionsFile, collections);
}
