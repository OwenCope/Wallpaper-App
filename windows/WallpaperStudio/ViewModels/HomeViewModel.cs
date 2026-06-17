using System.Collections.ObjectModel;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Media;
using CommunityToolkit.Mvvm.Input;
using WallpaperStudio.Services;

namespace WallpaperStudio.ViewModels;

public class CategoryTile
{
    public string Name { get; init; } = "";
    public string Query { get; init; } = "";
    public IBrush Brush { get; init; } = Brushes.Gray;

    public static CategoryTile Make(string name, string query, string c1, string c2) => new()
    {
        Name = name,
        Query = query,
        Brush = new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(Color.Parse(c1), 0),
                new GradientStop(Color.Parse(c2), 1),
            },
        },
    };
}

public partial class HomeViewModel : ViewModelBase
{
    public ObservableCollection<PhotoVM> Featured { get; } = new();

    public CategoryTile[] Categories { get; } =
    {
        CategoryTile.Make("Nature",    "nature landscape",   "#2E7D32", "#1B5E20"),
        CategoryTile.Make("Animals",   "animals wildlife",   "#8D6E63", "#4E342E"),
        CategoryTile.Make("Tech",      "technology setup",   "#37474F", "#102027"),
        CategoryTile.Make("Space",     "space galaxy stars", "#311B92", "#000000"),
        CategoryTile.Make("Minimal",   "minimal abstract",   "#546E7A", "#263238"),
        CategoryTile.Make("Mountains", "mountains",          "#455A64", "#1C313A"),
        CategoryTile.Make("Ocean",     "ocean sea water",    "#0277BD", "#01579B"),
        CategoryTile.Make("Forest",    "forest trees",       "#2E7D32", "#0D3010"),
    };

    public HomeViewModel() => _ = LoadFeaturedAsync();

    private async Task LoadFeaturedAsync()
    {
        try
        {
            var r = await AppState.Current.Wallhaven.SearchAsync("nature landscape", 1, "toplist", AppState.Current.Settings.ApiKey);
            if (r is null) return;
            int n = 0;
            foreach (var p in r.Data)
            {
                if (n++ >= 8) break;
                var vm = new PhotoVM(p);
                Featured.Add(vm);
                _ = vm.LoadThumbAsync();
            }
        }
        catch { /* offline */ }
    }

    [RelayCommand]
    private void OpenCategory(CategoryTile tile) => AppState.Current.Navigate?.Invoke("Explore", tile.Query);
}
