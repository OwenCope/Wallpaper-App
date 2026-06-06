import AppKit
import AVFoundation
import AVKit

/// Plays a looping video as a "live wallpaper" by parking borderless windows
/// at the desktop-window level — behind your icons — on every screen.
///
/// Note: macOS has no official live-wallpaper API. This sits a window just below
/// the desktop icon layer; it survives space changes but is inherently a bit of
/// a hack (it won't render on the login screen, etc.).
@MainActor
final class LiveWallpaperController: ObservableObject {
    static let shared = LiveWallpaperController()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentVideo: URL?

    private var windows: [NSWindow] = []
    private var players: [AVPlayer] = []
    private var loopObservers: [Any] = []

    func start(video url: URL) {
        stop()
        currentVideo = url

        for screen in NSScreen.screens {
            let player = AVPlayer(url: url)
            player.isMuted = true
            player.actionAtItemEnd = .none

            // Seamless loop.
            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main) { _ in
                    player.seek(to: .zero)
                    player.play()
                }
            loopObservers.append(observer)

            // Raw AVPlayerLayer (no AVPlayerView chrome / "can't play" placeholder).
            let playerView = PlayerLayerView()
            playerView.playerLayer.player = player
            playerView.playerLayer.videoGravity = .resizeAspectFill

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.backgroundColor = .black
            window.ignoresMouseEvents = true
            window.contentView = playerView
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()

            player.play()
            windows.append(window)
            players.append(player)
        }
        isPlaying = true
    }

    func stop() {
        players.forEach { $0.pause() }
        loopObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windows.forEach { $0.orderOut(nil) }
        players.removeAll()
        windows.removeAll()
        loopObservers.removeAll()
        isPlaying = false
        currentVideo = nil
    }
}

/// A layer-backed view that hosts an AVPlayerLayer filling its bounds.
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
