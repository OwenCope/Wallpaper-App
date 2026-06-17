using System.Collections.ObjectModel;
using System.IO;
using System.Threading.Tasks;
using Avalonia.Platform.Storage;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WallpaperStudio.Services;

namespace WallpaperStudio.ViewModels;

public partial class LibraryViewModel : ViewModelBase
{
    public ObservableCollection<LibItem> Items { get; } = new();

    [ObservableProperty] private bool _empty = true;
    [ObservableProperty] private string? _folderName;

    public LibraryViewModel() => Reload();

    public void Reload()
    {
        Items.Clear();
        var folder = AppState.Current.Settings.Folder;
        FolderName = string.IsNullOrEmpty(folder) ? null : Path.GetFileName(folder.TrimEnd('/', '\\'));
        foreach (var p in LibraryService.Images(folder))
            Items.Add(new LibItem(p));
        Empty = Items.Count == 0;
    }

    /// <summary>Invoked from the view (it owns the TopLevel needed for the OS folder picker).</summary>
    public async Task PickFolderAsync(IStorageProvider storage)
    {
        var result = await storage.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            AllowMultiple = false,
            Title = "Choose a wallpaper folder",
        });
        if (result.Count == 0) return;
        var path = result[0].TryGetLocalPath();
        if (string.IsNullOrEmpty(path)) return;
        AppState.Current.Settings.Folder = path;
        AppState.Current.SaveSettings();
        Reload();
    }

    [RelayCommand]
    private void Shuffle() => AppState.Current.Rotation.ShuffleNow();
}
