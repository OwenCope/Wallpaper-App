import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var rotation: RotationManager
    @AppStorage("wallhaven.apiKey") private var apiKey = ""

    var body: some View {
        Form {
            Section("Rotation") {
                Picker("Interval", selection: $rotation.interval) {
                    ForEach(RotationManager.Interval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                Toggle("Rotate favorites only", isOn: $rotation.favoritesOnly)
                Toggle("Apply to all displays", isOn: $rotation.allScreens)
            }
            Section("Wallhaven") {
                SecureField("API key (optional)", text: $apiKey)
                Text("Only needed if you hit the rate limit or want NSFW results. Get one at wallhaven.cc/settings/account.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Credits") {
                LabeledContent("Wallpapers", value: "Wallhaven")
                LabeledContent("Skin renders", value: "Starlight Skins · mc-heads · Minotar")
                LabeledContent("Minecraft assets", value: "© Mojang / Microsoft")
                Text("Not affiliated with or endorsed by Mojang. For personal use.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 460)
    }
}
