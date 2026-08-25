import AVFoundation
import Combine
import MediaPlayer
import UIKit

enum NavigationMusicService: String, CaseIterable, Identifiable {
    case appleMusic
    case youtubeMusic
    case youtube

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .youtubeMusic: "YouTube Music"
        case .youtube: "YouTube"
        }
    }

    var symbolName: String {
        switch self {
        case .appleMusic: "music.note"
        case .youtubeMusic: "music.note.list"
        case .youtube: "play.rectangle.fill"
        }
    }
}

@MainActor
final class NavigationMusicController: NSObject, ObservableObject {
    @Published private(set) var title = "음악을 연결해 보세요"
    @Published private(set) var artist = "Apple Music · YouTube Music · YouTube"
    @Published private(set) var artwork: UIImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var hasNowPlayingItem = false
    @Published private(set) var isOtherAudioPlaying = false
    @Published private(set) var isExternalAudioPlaying = false
    @Published private(set) var authorizationStatus = MPMediaLibrary.authorizationStatus()

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var isObserving = false
    private static let authorizationDidChange = Notification.Name("CoFFMapMusicAuthorizationDidChange")

    var canRequestAccess: Bool { authorizationStatus == .notDetermined }
    var canControlMusic: Bool { authorizationStatus == .authorized && hasNowPlayingItem }

    func startObserving() {
        guard !isObserving else {
            refresh()
            return
        }

        isObserving = true
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handlePlayerChange),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player
        )
        center.addObserver(
            self,
            selector: #selector(handlePlayerChange),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player
        )
        center.addObserver(
            self,
            selector: #selector(handlePlayerChange),
            name: Self.authorizationDidChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handlePlayerChange),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handlePlayerChange),
            name: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: nil
        )
        refresh()
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        NotificationCenter.default.removeObserver(self)
        player.endGeneratingPlaybackNotifications()
    }

    func requestAccess() {
        MPMediaLibrary.requestAuthorization { _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.authorizationDidChange, object: nil)
            }
        }
    }

    func togglePlayback() {
        guard canControlMusic else { return }
        isPlaying ? player.pause() : player.play()
        refresh()
    }

    func skipToPrevious() {
        guard canControlMusic else { return }
        player.skipToPreviousItem()
    }

    func skipToNext() {
        guard canControlMusic else { return }
        player.skipToNextItem()
    }

    func connectionDescription(for service: NavigationMusicService) -> String {
        switch service {
        case .appleMusic:
            if canControlMusic {
                return "현재 곡을 길안내 화면에서 제어할 수 있어요"
            }
            switch authorizationStatus {
            case .notDetermined:
                return "접근을 허용하면 곡 정보와 재생 버튼을 보여줘요"
            case .denied, .restricted:
                return "설정에서 미디어 보관함 접근을 허용해 주세요"
            case .authorized:
                return "Apple Music에서 음악을 재생해 주세요"
            @unknown default:
                return "Apple Music을 열어 연결해 주세요"
            }

        case .youtubeMusic, .youtube:
            return isExternalAudioPlaying
                ? "외부 음악이 재생 중이에요 · 앱으로 돌아가기"
                : "앱을 열어 음악을 재생해 주세요"
        }
    }

    func connect(to service: NavigationMusicService) {
        switch service {
        case .appleMusic:
            switch authorizationStatus {
            case .notDetermined:
                requestAccess()
            case .denied, .restricted:
                open(URL(string: UIApplication.openSettingsURLString))
            case .authorized:
                guard !canControlMusic else { return }
                open(URL(string: "music://"), fallback: URL(string: "https://music.apple.com"))
            @unknown default:
                open(URL(string: "music://"), fallback: URL(string: "https://music.apple.com"))
            }

        case .youtubeMusic:
            open(
                URL(string: "youtubemusic://"),
                fallback: URL(string: "https://music.youtube.com")
            )

        case .youtube:
            open(
                URL(string: "youtube://"),
                fallback: URL(string: "https://www.youtube.com")
            )
        }
    }

    @objc private func handlePlayerChange() {
        refresh()
    }

    private func refresh() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
        isOtherAudioPlaying = AVAudioSession.sharedInstance().isOtherAudioPlaying

        let item = authorizationStatus == .authorized ? player.nowPlayingItem : nil
        let appleMusicIsPlaying = item != nil && player.playbackState == .playing

        // 시스템 Music 플레이어에는 마지막 Apple Music 항목이 남아 있을 수 있습니다.
        // 그 항목이 멈춰 있고 다른 앱 오디오가 들리면 YouTube 계열 같은 외부 재생을
        // 우선 표시합니다. iOS는 외부 앱의 이름이나 곡 메타데이터까지는 공개하지 않습니다.
        if isOtherAudioPlaying && !appleMusicIsPlaying {
            artwork = nil
            hasNowPlayingItem = false
            isPlaying = false
            isExternalAudioPlaying = true
            title = "외부 앱에서 음악 재생 중"
            artist = "연결을 눌러 재생 중인 앱으로 돌아가세요"
            return
        }

        isExternalAudioPlaying = false

        guard authorizationStatus == .authorized, let item else {
            artwork = nil
            hasNowPlayingItem = false
            isPlaying = false
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                title = "음악 접근이 꺼져 있어요"
                artist = "YouTube Music·YouTube는 계속 연결할 수 있어요"
            } else {
                title = "음악을 연결해 보세요"
                artist = "Apple Music · YouTube Music · YouTube"
            }
            return
        }

        title = item.title ?? "제목 없는 곡"
        artist = item.artist ?? item.albumTitle ?? "Apple Music"
        artwork = item.artwork?.image(at: CGSize(width: 96, height: 96))
        hasNowPlayingItem = true
        isPlaying = player.playbackState == .playing
    }

    private func open(_ primaryURL: URL?, fallback fallbackURL: URL? = nil) {
        guard let primaryURL else { return }
        UIApplication.shared.open(primaryURL, options: [:]) { opened in
            guard !opened, let fallbackURL else { return }
            DispatchQueue.main.async {
                UIApplication.shared.open(fallbackURL)
            }
        }
    }
}
