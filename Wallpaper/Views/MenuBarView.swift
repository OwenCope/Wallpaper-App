import SwiftUI

/// Compact control center shown from the menu bar icon.
struct MenuBarView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rotation: RotationManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Wallpaper")
                    .font(.headline)

                Button {
                    rotation.rotateNow()
                } label: {
                    Label("Shuffle now", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                Picker("Auto-rotate", selection: $rotation.interval) {
                    ForEach(RotationManager.Interval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Favorites only", isOn: $rotation.favoritesOnly)
                Toggle("All displays", isOn: $rotation.allScreens)

                Divider()

                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open Library", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(width: 260)
    }
}
