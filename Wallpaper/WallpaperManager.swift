import AppKit

/// Thin wrapper around the macOS APIs that actually change the desktop picture.
enum WallpaperManager {

    /// Set the wallpaper on every connected display.
    static func setOnAllScreens(_ url: URL) {
        for screen in NSScreen.screens {
            try? apply(url, to: screen)
        }
    }

    /// Set the wallpaper on the screen that currently has the mouse/key window.
    static func setOnMainScreen(_ url: URL) {
        if let screen = NSScreen.main {
            try? apply(url, to: screen)
        }
    }

    /// Set the wallpaper on one specific display.
    static func set(_ url: URL, on screen: NSScreen) {
        try? apply(url, to: screen)
    }

    private static func apply(_ url: URL, to screen: NSScreen) throws {
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        var newOptions = options
        // .scaleProportionallyUpOrDown == 1; fill the screen, allow clipping.
        newOptions[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
        newOptions[.allowClipping] = true
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: newOptions)
    }
}
