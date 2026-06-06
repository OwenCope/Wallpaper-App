import SwiftUI
import Combine

/// Drives automatic wallpaper rotation on a timer.
@MainActor
final class RotationManager: ObservableObject {
    enum Interval: String, CaseIterable, Identifiable {
        case off, fifteenMinutes, hour, sixHours, day
        var id: String { rawValue }

        var seconds: TimeInterval? {
            switch self {
            case .off: return nil
            case .fifteenMinutes: return 15 * 60
            case .hour: return 60 * 60
            case .sixHours: return 6 * 60 * 60
            case .day: return 24 * 60 * 60
            }
        }

        var label: String {
            switch self {
            case .off: return "Off"
            case .fifteenMinutes: return "Every 15 minutes"
            case .hour: return "Every hour"
            case .sixHours: return "Every 6 hours"
            case .day: return "Every day"
            }
        }
    }

    @AppStorage("rotation.interval") private var storedInterval = Interval.off.rawValue
    @AppStorage("rotation.favoritesOnly") var favoritesOnly = false
    @AppStorage("rotation.allScreens") var allScreens = true

    @Published var interval: Interval = .off { didSet { storedInterval = interval.rawValue; restart() } }

    private var timer: Timer?
    private weak var library: LibraryStore?

    func attach(library: LibraryStore) {
        self.library = library
        interval = Interval(rawValue: storedInterval) ?? .off
        restart()
    }

    func restart() {
        timer?.invalidate()
        timer = nil
        guard let seconds = interval.seconds else { return }
        let t = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rotateNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func rotateNow() {
        guard let library,
              let next = library.randomImage(favoritesOnly: favoritesOnly) else { return }
        library.setWallpaper(next, allScreens: allScreens)
    }
}
