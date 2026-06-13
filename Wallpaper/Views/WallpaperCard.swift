import SwiftUI

/// App color tokens to match the Wallspace dark aesthetic.
enum Theme {
    /// Adaptive so the app follows the system appearance: near-black in dark, near-white in light.
    static let background = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .black : NSColor(white: 0.96, alpha: 1)
    })
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
            : NSColor(white: 0.91, alpha: 1)
    })
    static let cornerRadius: CGFloat = 14
}

/// A large wallpaper card with hover-reveal controls. Image content is injected
/// so the same card serves local files and remote thumbnails.
struct WallpaperCard<Img: View>: View {
    @ViewBuilder var image: () -> Img
    var caption: String? = nil
    var badge: String? = nil          // e.g. "NEW" / "PRO"
    var rank: Int? = nil              // big ranking number, bottom-left
    var height: CGFloat = 165
    var isFavorite: Bool = false
    var isBusy: Bool = false
    var isCurrent: Bool = false
    var onSet: () -> Void
    var onFavorite: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        image()
            .aspectRatio(16 / 9, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay { gradientScrim }
            .overlay(alignment: .bottomLeading) { rankNumber }
            .overlay(alignment: .topLeading) { badgeView }
            .overlay(alignment: .topTrailing) { favoriteButton }
            .overlay(alignment: .bottom) { hoverControls }
            .overlay(alignment: .bottomTrailing) { captionBadge }
            .overlay { if isBusy { busyOverlay } }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(.tint, lineWidth: isCurrent ? 3 : 0)
            }
            .clipShape(.rect(cornerRadius: Theme.cornerRadius))
            .shadow(color: .black.opacity(hovering ? 0.4 : 0.22),
                    radius: hovering ? 16 : 9, y: hovering ? 8 : 5)
            .scaleEffect(hovering ? 1.015 : 1)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .onTapGesture { onSet() }
    }

    private var gradientScrim: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(hovering ? 0.55 : 0.25)],
            startPoint: .center, endPoint: .bottom)
        .animation(.easeOut(duration: 0.18), value: hovering)
    }

    @ViewBuilder
    private var rankNumber: some View {
        if let rank {
            Text("\(rank)")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6)
                .padding(.leading, 14).padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Text(badge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(badge == "PRO" ? AnyShapeStyle(.orange.gradient) : AnyShapeStyle(.blue.gradient),
                            in: .capsule)
                .padding(10)
        }
    }

    @ViewBuilder
    private var hoverControls: some View {
        if hovering {
            Button(action: onSet) {
                Label("Set Wallpaper", systemImage: "checkmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if let onFavorite, hovering || isFavorite {
            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isFavorite ? .pink : .white)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(10)
        }
    }

    @ViewBuilder
    private var captionBadge: some View {
        if let caption {
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                .padding(10)
                .opacity(hovering ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            ProgressView().controlSize(.large).tint(.white)
        }
    }
}

extension Array where Element == GridItem {
    static var wallpaperColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 16)]
    }
}
