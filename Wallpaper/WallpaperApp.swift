import SwiftUI
import AppKit

/// Ensures the app shows up front when launched, instead of opening its window
/// behind whatever is currently on screen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    // Re-open the window if the user clicks the Dock icon with no windows open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.activate(ignoringOtherApps: true) }
        return true
    }
}

@main
struct WallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Shared app-wide state. These outlive any single window.
    @StateObject private var library = LibraryStore()
    @StateObject private var rotation = RotationManager()
    @StateObject private var collections = CollectionStore()
    @StateObject private var live = LiveWallpaperController.shared
    @StateObject private var preview = PreviewCoordinator()

    var body: some Scene {
        // Main browsing window.
        Window("Wallpaper", id: "main") {
            ContentView()
                .environmentObject(library)
                .environmentObject(rotation)
                .environmentObject(collections)
                .environmentObject(live)
                .environmentObject(preview)
                .frame(minWidth: 960, minHeight: 680)
                .preferredColorScheme(.dark)
                .onAppear { rotation.attach(library: library) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 860)

        // Menu bar control center — quick access without opening the window.
        MenuBarExtra("Wallpaper", systemImage: "photo.on.rectangle.angled") {
            MenuBarView()
                .environmentObject(library)
                .environmentObject(rotation)
                .environmentObject(live)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(rotation)
        }
    }
}
