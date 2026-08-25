//
//  UserProfile.swift
//  CoFFMap
//
//  사용자가 직접 꾸미는 프로필. 사진을 쓰거나, 애플 이모지로 아바타를 만들 수 있습니다.
//  사진은 앱 문서 폴더에 리사이즈해서 저장하고, 나머지 설정은 UserDefaults에 둡니다.
//

import Combine
import Foundation
import SwiftUI
import UIKit

struct UserProfile: Codable, Equatable {
    enum Appearance: Codable, Equatable {
        /// 애플 이모지 + 배경색
        case emoji(String, colorID: String)
        /// 문서 폴더에 저장된 사진 파일 이름
        case photo(fileName: String)
    }

    /// 비워 두면 Apple 계정 이름을 그대로 씁니다.
    var nickname: String
    var appearance: Appearance

    static let `default` = UserProfile(
        nickname: "",
        appearance: .emoji("🙂", colorID: "blue")
    )

    var emoji: String? {
        if case .emoji(let value, _) = appearance { return value }
        return nil
    }

    var colorID: String {
        if case .emoji(_, let colorID) = appearance { return colorID }
        return CategoryPalette.fallbackID
    }

    var photoFileName: String? {
        if case .photo(let fileName) = appearance { return fileName }
        return nil
    }

    /// 계정 이름과 합쳐서 실제로 보여 줄 이름.
    func displayName(fallback: String?) -> String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return fallback ?? "나"
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profile: UserProfile = .default
    /// 사진 프로필일 때의 이미지. 화면에서 바로 쓸 수 있게 메모리에 들고 있습니다.
    @Published private(set) var photo: UIImage?

    private let defaults: UserDefaults
    private let profileKey = "fastmap.profile.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Mutations

    func updateNickname(_ nickname: String) {
        profile.nickname = nickname
        persist()
    }

    func useEmoji(_ emoji: String, colorID: String) {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? "🙂" : String(trimmed.prefix(2))
        removeStoredPhotoFile()
        photo = nil
        profile.appearance = .emoji(value, colorID: colorID)
        persist()
    }

    /// 촬영하거나 앨범에서 고른 사진을 프로필로 씁니다.
    func usePhoto(_ image: UIImage) {
        let resized = ProfileStore.resized(image, maxDimension: 512)
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return }

        let fileName = "profile-\(Int(Date().timeIntervalSince1970)).jpg"
        let url = ProfileStore.photosDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(
                at: ProfileStore.photosDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }

        removeStoredPhotoFile()
        profile.appearance = .photo(fileName: fileName)
        photo = resized
        persist()
    }

    /// 사진을 지우고 기본 이모지 아바타로 되돌립니다.
    func resetToEmoji() {
        useEmoji("🙂", colorID: CategoryPalette.fallbackID)
    }

    // MARK: - Persistence

    private static var photosDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("FastMapProfile", isDirectory: true)
    }

    private func load() {
        if let data = defaults.data(forKey: profileKey),
           let stored = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = stored
        }

        if let fileName = profile.photoFileName {
            let url = ProfileStore.photosDirectory.appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                photo = image
            } else {
                // 파일이 사라졌으면 기본 아바타로 되돌립니다.
                profile.appearance = UserProfile.default.appearance
                persist()
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: profileKey)
    }

    private func removeStoredPhotoFile() {
        guard let fileName = profile.photoFileName else { return }
        let url = ProfileStore.photosDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static var preview: ProfileStore {
        ProfileStore(defaults: UserDefaults(suiteName: "fastmap.preview") ?? .standard)
    }
}

// MARK: - 이모지 카탈로그

/// 아바타로 쓸 만한 애플 기본 이모지 모음.
enum ProfileEmojiCatalog {
    struct Group: Identifiable {
        let id: String
        let title: String
        let emojis: [String]
    }

    static let groups: [Group] = [
        Group(id: "face", title: "표정", emojis: [
            "🙂", "😀", "😄", "😎", "🤓", "🥳", "😌", "🤩", "😴", "🫠",
            "🙃", "😇", "🤔", "😐", "🥹", "😺"
        ]),
        Group(id: "people", title: "사람", emojis: [
            "🧑", "👩", "👨", "🧑‍💻", "🧑‍🎨", "🧑‍🍳", "🧑‍🚀", "🕵️", "🏃", "🚶",
            "🧗", "🧘", "💁", "🙋"
        ]),
        Group(id: "animal", title: "동물", emojis: [
            "🐱", "🐶", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐸",
            "🐧", "🦉", "🐢", "🦋", "🐝", "🦄"
        ]),
        Group(id: "nature", title: "자연 · 음식", emojis: [
            "🌱", "🌿", "🍀", "🌵", "🌻", "🌙", "⭐️", "🔥", "🌈", "❄️",
            "☕️", "🍩", "🍜", "🍎", "🍔", "🍰"
        ]),
        Group(id: "object", title: "사물 · 이동", emojis: [
            "🗺️", "📍", "🧭", "🎧", "📚", "🎮", "🚲", "🛴", "🚗", "✈️",
            "⚽️", "🎸", "💡", "🔑", "🎯", "🏔️"
        ])
    ]

    static let all: [String] = groups.flatMap(\.emojis)

    /// 입력된 문자열에서 이모지 한 글자만 뽑아냅니다.
    static func firstEmoji(in text: String) -> String? {
        text.first { character in
            character.unicodeScalars.contains { $0.properties.isEmoji && $0.properties.isEmojiPresentation }
                || character.unicodeScalars.count > 1
        }
        .map(String.init)
    }
}
