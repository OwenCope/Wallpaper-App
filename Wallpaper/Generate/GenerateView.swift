import SwiftUI

struct GenerateView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rotation: RotationManager
    @State private var status: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Gradient wallpapers")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 20).padding(.top, 16)
                Text("Rendered at your screen resolution and set instantly.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                LazyVGrid(columns: .wallpaperColumns, spacing: 18) {
                    ForEach(GradientGenerator.presets) { preset in
                        GradientCell(preset: preset)
                            .onTapGesture { apply(preset) }
                    }
                }
                .padding(20)

                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }

                // Pointer to the dynamic (time-of-day) builder.
                GlassEffectContainer {
                    HStack(spacing: 12) {
                        Image(systemName: "sun.max").font(.title2)
                        VStack(alignment: .leading) {
                            Text("Time-of-day dynamic wallpaper").font(.headline)
                            Text("Build a macOS .heic that shifts with light/dark or the sun.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Build…") { buildDynamic() }
                            .buttonStyle(.glassProminent)
                    }
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
                .padding(20)
            }
        }
        .navigationTitle("Generate")
    }

    private func apply(_ preset: GradientGenerator.Preset) {
        guard let url = GradientGenerator.render(preset) else { status = "Render failed."; return }
        library.setWallpaper(url, allScreens: rotation.allScreens)
        status = "Set “\(preset.name)” as wallpaper."
    }

    /// Pick a light + dark image and bundle them into a dynamic .heic.
    private func buildDynamic() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.message = "Pick 2 images: first = light appearance, second = dark."
        guard panel.runModal() == .OK, panel.urls.count >= 2 else { return }
        let dest = AppPaths.generated.appendingPathComponent("dynamic-\(panel.urls.count).heic")
        do {
            try DynamicHEICBuilder.buildLightDark(light: panel.urls[0], dark: panel.urls[1], to: dest)
            library.setWallpaper(dest, allScreens: rotation.allScreens)
            status = "Built dynamic wallpaper and set it. It now follows light/dark mode."
        } catch {
            status = "Couldn't build dynamic wallpaper: \(error.localizedDescription)"
        }
    }
}

private struct GradientCell: View {
    let preset: GradientGenerator.Preset
    @State private var hovering = false
    var body: some View {
        LinearGradient(colors: preset.colors,
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(height: 190)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(alignment: .bottomLeading) {
                Text(preset.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                    .padding(10)
            }
            .shadow(color: .black.opacity(hovering ? 0.3 : 0.16),
                    radius: hovering ? 14 : 8, y: hovering ? 8 : 4)
            .scaleEffect(hovering ? 1.015 : 1)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
    }
}
