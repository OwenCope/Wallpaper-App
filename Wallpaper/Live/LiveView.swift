import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var live: LiveWallpaperController

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 18) {
                    Image(systemName: live.isPlaying ? "play.rectangle.fill" : "play.rectangle")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(.secondary)

                    Text(live.isPlaying ? "Live wallpaper is running" : "Live wallpaper")
                        .font(.title2.weight(.semibold))

                    Text(live.currentVideo?.lastPathComponent
                         ?? "Pick a looping video (.mp4/.mov). It plays behind your desktop icons on every display.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    HStack(spacing: 12) {
                        Button { pick() } label: {
                            Label("Choose Video", systemImage: "film")
                                .padding(.horizontal, 8).padding(.vertical, 4)
                        }
                        .buttonStyle(.glassProminent)

                        if live.isPlaying {
                            Button(role: .destructive) { live.stop() } label: {
                                Label("Stop", systemImage: "stop.fill")
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                            }
                            .buttonStyle(.glass)
                        }
                    }

                    Text("Note: macOS has no official live-wallpaper API, so this is a best-effort overlay. It won't appear on the login screen and may use more energy.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                .padding(40)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
            }
            .padding(.top, 60)
        }
        .navigationTitle("Live")
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        live.start(video: url)
    }
}
