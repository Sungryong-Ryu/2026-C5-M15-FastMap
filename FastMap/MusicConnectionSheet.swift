import SwiftUI

struct MusicConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var music: NavigationMusicController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TossSpacing.l) {
                    HStack(spacing: TossSpacing.l) {
                        Image(systemName: music.isExternalAudioPlaying ? "waveform" : "music.note")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 70)
                            .background(MusicGradient.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: TossColor.blue.opacity(0.32), radius: 18, y: 8)

                        VStack(alignment: .leading, spacing: TossSpacing.xs) {
                            Text(music.isExternalAudioPlaying ? "재생 중인 음악 앱을 선택하세요" : "음악 앱을 연결하세요")
                                .font(TossFont.title2)
                                .foregroundStyle(TossColor.textPrimary)
                                .tossTextContrast()

                            Text("길안내를 멈추지 않고 사용하던 음악 앱으로 이동할 수 있어요.")
                                .font(TossFont.body)
                                .foregroundStyle(TossColor.textSecondary)
                                .tossTextContrast()
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(NavigationMusicService.allCases.enumerated()), id: \.element.id) { index, service in
                            serviceButton(service)

                            if index < NavigationMusicService.allCases.count - 1 {
                                TossDivider(leadingInset: 64)
                            }
                        }
                    }
                    .tossCard()

                    Label(
                        "iOS에서는 YouTube Music과 YouTube의 재생 여부만 감지할 수 있어요. 곡 제목과 재생 버튼은 해당 앱에서 이용해 주세요.",
                        systemImage: "info.circle"
                    )
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textTertiary)
                }
                .padding(.horizontal, TossEdge.screenInset)
                .padding(.vertical, TossSpacing.xl)
            }
            .scrollIndicators(.hidden)
            .tossPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("음악 연결")
                        .font(TossFont.title3)
                        .foregroundStyle(TossColor.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                        .font(TossFont.headline)
                        .foregroundStyle(TossColor.blue)
                }
            }
            .toolbarBackground(TossColor.background.opacity(0.88), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
    }

    private func serviceButton(_ service: NavigationMusicService) -> some View {
        Button {
            music.connect(to: service)
            dismiss()
        } label: {
            HStack(spacing: TossSpacing.m) {
                Image(systemName: service.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor(for: service))
                    .frame(width: 44, height: 44)
                    .background(iconColor(for: service).opacity(0.12), in: RoundedRectangle(cornerRadius: TossRadius.icon))

                VStack(alignment: .leading, spacing: 3) {
                    Text(service.title)
                        .font(TossFont.bodyStrong)
                        .foregroundStyle(TossColor.textPrimary)
                    Text(music.connectionDescription(for: service))
                        .font(TossFont.footnote)
                        .foregroundStyle(TossColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TossColor.textTertiary)
            }
            .padding(.horizontal, TossSpacing.m)
            .padding(.vertical, TossSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(service.title) 연결")
        .accessibilityHint(music.connectionDescription(for: service))
    }

    private func iconColor(for service: NavigationMusicService) -> Color {
        switch service {
        case .appleMusic: Color(red: 0.98, green: 0.18, blue: 0.33)
        case .youtubeMusic, .youtube: Color(red: 1, green: 0, blue: 0)
        }
    }
}
