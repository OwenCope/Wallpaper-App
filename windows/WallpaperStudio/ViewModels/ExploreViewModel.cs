using System.Collections.ObjectModel;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WallpaperStudio.Services;

namespace WallpaperStudio.ViewModels;

public partial class ExploreViewModel : ViewModelBase
{
    public ObservableCollection<PhotoVM> Results { get; } = new();

    [ObservableProperty] private string _query = "";
    [ObservableProperty] private bool _busy;
    [ObservableProperty] private bool _empty;

    private int _page = 1;
    private int _lastPage = 1;

    public ExploreViewModel() => _ = LoadMoreCommand.ExecuteAsync(null);

    [RelayCommand]
    private async Task Search()
    {
        _page = 1;
        _lastPage = 1;
        Results.Clear();
        await LoadMore();
    }

    [RelayCommand]
    private async Task LoadMore()
    {
        if (Busy || _page > _lastPage) return;
        Busy = true;
        try
        {
            var sorting = string.IsNullOrWhiteSpace(Query) ? "toplist" : "relevance";
            var r = await AppState.Current.Wallhaven.SearchAsync(Query, _page, sorting, AppState.Current.Settings.ApiKey);
            if (r is not null)
            {
                _lastPage = r.Meta.LastPage <= 0 ? _page : r.Meta.LastPage;
                foreach (var p in r.Data)
                {
                    var vm = new PhotoVM(p);
                    Results.Add(vm);
                    _ = vm.LoadThumbAsync();
                }
                _page++;
            }
        }
        catch { /* offline / rate limited */ }
        finally
        {
            Busy = false;
            Empty = Results.Count == 0;
        }
    }
}
