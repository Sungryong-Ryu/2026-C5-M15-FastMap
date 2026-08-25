//
//  ProfileEditorView.swift
//  CoFFMap
//
//  프로필 꾸미기. 사진(촬영 / 앨범)과 애플 이모지 아바타 중에서 고를 수 있습니다.
//

import PhotosUI
import SwiftUI
import UIKit

// MARK: - 아바타

/// 앱 곳곳에서 쓰는 프로필 아바타.
struct ProfileAvatarView: View {
    let profile: UserProfile
    let photo: UIImage?
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                CategoryPalette.color(for: profile.colorID).opacity(0.24)
                Text(profile.emoji ?? "🙂")
                    .font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(TossColor.line, lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

// MARK: - 편집 화면

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore

    private enum Style: String, CaseIterable, Identifiable {
        case emoji
        case photo

        var id: String { rawValue }
        var title: String {
            switch self {
            case .emoji: "이모지"
            case .photo: "사진"
            }
        }
    }

    @State private var style: Style = .emoji
    @State private var nickname = ""
    @State private var selectedEmoji = "🙂"
    @State private var selectedColorID = CategoryPalette.fallbackID
    @State private var pickedPhoto: UIImage?
    @State private var photosItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var customEmojiInput = ""
    @FocusState private var isNicknameFocused: Bool

    private let emojiColumns = Array(repeating: GridItem(.flexible(), spacing: TossSpacing.s), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TossSpacing.xxl) {
                    avatarPreview
                    nicknameSection
                    styleSwitcher

                    switch style {
                    case .emoji: emojiSection
                    case .photo: photoSection
                    }
                }
                .padding(.horizontal, TossEdge.screenInset)
                .padding(.top, TossSpacing.s)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .tossPageBackground(tone: .sunset)
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("프로필 꾸미기")
                        .font(TossFont.title3)
                        .foregroundStyle(TossColor.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .font(TossFont.headline)
                        .foregroundStyle(TossColor.textSecondary)
                }
            }
            .toolbarBackground(TossColor.background.opacity(0.88), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker(
                    onCapture: { image in
                        pickedPhoto = image
                        style = .photo
                    },
                    onFinish: { isShowingCamera = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: photosItem) { _, newItem in
                loadPickedPhoto(newItem)
            }
            .onAppear(perform: prepare)
        }
    }

    // MARK: 미리보기

    private var previewProfile: UserProfile {
        UserProfile(
            nickname: nickname,
            appearance: style == .photo && pickedPhoto != nil
                ? .photo(fileName: "preview")
                : .emoji(selectedEmoji, colorID: selectedColorID)
        )
    }

    private var avatarPreview: some View {
        HStack(spacing: TossSpacing.l) {
            ProfileAvatarView(
                profile: previewProfile,
                photo: style == .photo ? pickedPhoto : nil,
                size: 72
            )
            .overlay {
                Circle()
                    .stroke(MusicGradient.warmAccent, lineWidth: 2.5)
                    .padding(-3)
            }
            .shadow(color: TossColor.red.opacity(0.26), radius: 16, y: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "이름 없음" : nickname)
                    .font(TossFont.title2)
                    .foregroundStyle(TossColor.textPrimary)
                    .lineLimit(1)

                Text(style == .photo ? "사진 프로필" : "이모지 아바타")
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TossSpacing.l)
        .background(MusicGradient.softWarm, in: RoundedRectangle(cornerRadius: TossRadius.card, style: .continuous))
        .tossCard()
    }

    // MARK: 닉네임

    private var nicknameSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            TossSectionHeader(title: "이름")

            TextField("앱에서 보여줄 이름", text: $nickname)
                .font(TossFont.body)
                .foregroundStyle(TossColor.textPrimary)
                .tint(TossColor.red)
                .focused($isNicknameFocused)
                .submitLabel(.done)
                .padding(.horizontal, TossSpacing.l)
                .frame(height: TossSize.fieldHeight)
                .background(TossColor.surfaceAlt, in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))
        }
    }

    // MARK: 스타일 전환

    private var styleSwitcher: some View {
        HStack(spacing: TossSpacing.xxs) {
            ForEach(Style.allCases) { option in
                Button {
                    withAnimation(TossMotion.quick) { style = option }
                } label: {
                    Text(option.title)
                        .font(TossFont.buttonSmall)
                        .foregroundStyle(style == option ? TossColor.textPrimary : TossColor.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            style == option
                                ? AnyShapeStyle(MusicGradient.softWarm)
                                : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(TossColor.surfaceAlt, in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))
    }

    // MARK: 이모지

    private var emojiSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.xl) {
            ForEach(ProfileEmojiCatalog.groups) { group in
                VStack(alignment: .leading, spacing: TossSpacing.m) {
                    Text(group.title)
                        .font(TossFont.captionStrong)
                        .foregroundStyle(TossColor.textSecondary)

                    LazyVGrid(columns: emojiColumns, spacing: TossSpacing.s) {
                        ForEach(group.emojis, id: \.self) { emoji in
                            Button {
                                selectedEmoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 26))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(
                                        selectedEmoji == emoji
                                            ? CategoryPalette.color(for: selectedColorID).opacity(0.24)
                                            : TossColor.surfaceAlt,
                                        in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                                    )
                            }
                            .buttonStyle(TossScaleButtonStyle())
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: TossSpacing.s) {
                Text("직접 입력")
                    .font(TossFont.captionStrong)
                    .foregroundStyle(TossColor.textSecondary)

                TextField("키보드에서 이모지를 골라 붙여 넣어도 돼요", text: $customEmojiInput)
                    .font(TossFont.body)
                    .tint(TossColor.blue)
                    .padding(.horizontal, TossSpacing.m)
                    .frame(height: 44)
                    .background(TossColor.surfaceAlt, in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))
                    .onChange(of: customEmojiInput) { _, newValue in
                        if let emoji = ProfileEmojiCatalog.firstEmoji(in: newValue) {
                            selectedEmoji = emoji
                        }
                    }
            }

            VStack(alignment: .leading, spacing: TossSpacing.m) {
                Text("배경색")
                    .font(TossFont.captionStrong)
                    .foregroundStyle(TossColor.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TossSpacing.m) {
                        ForEach(CategoryPalette.options) { option in
                            Button {
                                selectedColorID = option.id
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if selectedColorID == option.id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(TossScaleButtonStyle())
                            .accessibilityLabel(option.title)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: 사진

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            if CameraPicker.isAvailable {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("사진 찍기", systemImage: "camera.fill")
                }
                .buttonStyle(TossPrimaryButtonStyle(accent: .warm))
            }

            PhotosPicker(selection: $photosItem, matching: .images, photoLibrary: .shared()) {
                Label("앨범에서 고르기", systemImage: "photo.on.rectangle")
                    .font(TossFont.button)
                    .foregroundStyle(TossColor.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: TossSize.ctaHeight)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TossRadius.button, style: .continuous))
            }

            if pickedPhoto != nil || profileStore.photo != nil {
                Button("사진 지우고 이모지로 돌아가기") {
                    pickedPhoto = nil
                    photosItem = nil
                    withAnimation(TossMotion.quick) { style = .emoji }
                }
                .buttonStyle(
                    TossSecondaryButtonStyle(
                        height: TossSize.controlHeight,
                        foreground: TossColor.red,
                        background: TossColor.redWeak
                    )
                )
            }

            if !CameraPicker.isAvailable {
                Text("이 기기에서는 카메라를 쓸 수 없어 앨범만 사용할 수 있어요.")
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textTertiary)
            }
        }
    }

    // MARK: 저장

    private var saveBar: some View {
        Button("저장") { save() }
            .buttonStyle(TossPrimaryButtonStyle(accent: .warm))
            .padding(.horizontal, TossEdge.screenInset)
            .padding(.top, TossSpacing.m)
            .padding(.bottom, TossSpacing.s)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
    }

    // MARK: Actions

    private func prepare() {
        let profile = profileStore.profile
        nickname = profile.nickname
        selectedColorID = profile.colorID
        selectedEmoji = profile.emoji ?? "🙂"

        if let photo = profileStore.photo {
            pickedPhoto = photo
            style = .photo
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                pickedPhoto = image
                withAnimation(TossMotion.quick) { style = .photo }
            }
        }
    }

    private func save() {
        profileStore.updateNickname(nickname)

        if style == .photo, let pickedPhoto {
            profileStore.usePhoto(pickedPhoto)
        } else {
            profileStore.useEmoji(selectedEmoji, colorID: selectedColorID)
        }

        dismiss()
    }
}

// MARK: - 카메라

/// UIImagePickerController를 감싼 카메라 화면.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onFinish: () -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            if let image {
                onCapture(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
