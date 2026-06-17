using Avalonia.Controls;
using Avalonia.Interactivity;
using WallpaperStudio.ViewModels;

namespace WallpaperStudio.Views;

public partial class LibraryView : UserControl
{
    public LibraryView() => InitializeComponent();

    private async void OnPickFolder(object? sender, RoutedEventArgs e)
    {
        if (DataContext is LibraryViewModel vm)
        {
            var top = TopLevel.GetTopLevel(this);
            if (top is not null)
                await vm.PickFolderAsync(top.StorageProvider);
        }
    }
}
