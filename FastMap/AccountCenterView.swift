import AuthenticationServices
import CoreLocation
import SwiftUI

struct AccountCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var savedCafeStore: SavedCafeStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: CafeStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var isShowingProfileEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TossSpacing.xxl) {
                    profileCard

                    if accountManager.account != nil {
                        savedCafesSection
                        signOutSection
                    } else {
                        signInSection
                    }
                }
                .padding(.horizontal, TossEdge.screenInset)
                .padding(.top, TossSpacing.s)
                .padding(.bottom, TossSpacing.xxl)
            }
            .scrollIndicators(.hidden)
            .tossPageBackground(tone: .sunset)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("내 CoFFMap")
                        .font(TossFont.title3)
                        .foregroundStyle(TossColor.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                        .font(TossFont.headline)
                        .foregroundStyle(TossColor.textSecondary)
                }
            }
            .toolbarBackground(TossColor.background.opacity(0.88), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .sheet(isPresented: $isShowingProfileEditor) {
                ProfileEditorView()
                    .environmentObject(profileStore)
                    .presentationCornerRadius(TossRadius.sheet)
            }
        }
    }

    // MARK: - 프로필

    private var profileCard: some View {
        Button {
            isShowingProfileEditor = true
        } label: {
            HStack(spacing: TossSpacing.l) {
                ProfileAvatarView(profile: profileStore.profile, photo: profileStore.photo, size: 64)
                    .overlay {
                        Circle()
                            .stroke(MusicGradient.warmAccent, lineWidth: 2.5)
                            .padding(-3)
                    }
                    .shadow(color: TossColor.red.opacity(0.28), radius: 16, y: 6)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profileStore.profile.displayName(fallback: accountManager.account?.displayName))
                        .font(TossFont.title2)
                        .foregroundStyle(TossColor.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(TossFont.footnote)
                        .foregroundStyle(TossColor.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TossColor.textTertiary)
            }
            .padding(TossSpacing.l)
            .background(MusicGradient.softWarm, in: RoundedRectangle(cornerRadius: TossRadius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tossCard()
    }

    private var subtitle: String {
        if let email = accountManager.account?.email {
            return email
        }
        if accountManager.account != nil {
            return savedCafeStore.syncState.text
        }
        return "프로필을 눌러 사진이나 이모지로 꾸며 보세요"
    }

    // MARK: - 저장한 카페

    private var savedCafesSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            TossSectionHeader(
                title: "저장한 카페",
                trailing: savedCafeStore.cafes.isEmpty ? nil : "\(savedCafeStore.cafes.count)곳"
            )

            VStack(spacing: 0) {
                if savedCafeStore.cafes.isEmpty {
                    TossEmptyState(
                        systemImage: "bookmark",
                        title: "아직 저장한 카페가 없어요",
                        message: "카페 목록의 북마크 버튼을 눌러\n자주 가는 곳을 저장해 보세요."
                    )
                } else {
                    ForEach(Array(savedCafeStore.cafes.enumerated()), id: \.element.id) { index, cafe in
                        savedCafeRow(cafe)

                        if index < savedCafeStore.cafes.count - 1 {
                            TossDivider(leadingInset: 68)
                        }
                    }
                }
            }
            .padding(.vertical, TossSpacing.xxs)
            .tossCard()
        }
    }

    private func savedCafeRow(_ cafe: Cafe) -> some View {
        HStack(spacing: 0) {
            Button {
                let updatedCafe = cafe.rebased(from: locationService.currentLocation)
                Task {
                    await store.select(updatedCafe, from: locationService.currentLocation)
                    dismiss()
                }
            } label: {
                SavedCafeRow(cafe: cafe)
            }
            .buttonStyle(TossPressableStyle(cornerRadius: TossRadius.field))

            Button {
                Task { await savedCafeStore.remove(cafe) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(TossScaleButtonStyle())
            .accessibilityLabel("\(cafe.name) 저장 취소")
        }
        .padding(.trailing, TossSpacing.s)
    }

    private var signOutSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.s) {
            Button("로그아웃") {
                accountManager.signOut()
            }
            .buttonStyle(
                TossSecondaryButtonStyle(
                    foreground: TossColor.red,
                    background: TossColor.redWeak
                )
            )

            Text("로그아웃해도 iCloud에 저장된 카페는 삭제되지 않아요.")
                .font(TossFont.footnote)
                .foregroundStyle(TossColor.textTertiary)
                .padding(.horizontal, TossSpacing.xxs)
        }
    }

    // MARK: - 로그인

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.l) {
            Image(systemName: "heart.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(MusicGradient.warmAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: TossColor.red.opacity(0.28), radius: 18, y: 8)

            VStack(alignment: .leading, spacing: TossSpacing.s) {
                Text("좋아하는 카페,\n저장해 두세요")
                    .font(TossFont.title1)
                    .foregroundStyle(TossColor.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .tossTextContrast()

                Text("Apple 계정으로 로그인하면 카페를 저장하고\n같은 iCloud 계정의 기기에서 이어서 볼 수 있어요.")
                    .font(TossFont.body)
                    .foregroundStyle(TossColor.textSecondary)
                    .lineSpacing(3)
                    .tossTextContrast()
            }

            if let errorMessage = accountManager.errorMessage {
                Text(errorMessage)
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.red)
            }

            SignInWithAppleButton(.signIn) { request in
                accountManager.prepare(request)
            } onCompletion: { result in
                accountManager.complete(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: TossSize.ctaHeight)
            .clipShape(RoundedRectangle(cornerRadius: TossRadius.button, style: .continuous))
        }
        .padding(.top, TossSpacing.s)
    }
}

private struct SavedCafeRow: View {
    let cafe: Cafe

    var body: some View {
        HStack(spacing: TossSpacing.m) {
            TossIconBadge(
                systemName: cafe.orderedTags.first?.symbolName ?? "cup.and.saucer.fill",
                tint: cafe.orderedTags.first?.tint ?? TossCategoryColor.brown,
                size: 44
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(cafe.name)
                    .font(TossFont.headline)
                    .foregroundStyle(TossColor.textPrimary)
                    .lineLimit(1)
                Text(cafe.displayAddress)
                    .font(TossFont.caption)
                    .foregroundStyle(TossColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: TossSpacing.s)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TossColor.textTertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, TossSpacing.m)
        .padding(.horizontal, TossSpacing.l)
    }
}

/// 저장해 둔 카페는 거리·방위가 저장 당시 값이라 0입니다.
/// 목록에서 다시 고를 때 현위치 기준으로 계산해 줍니다.
private extension Cafe {
    func rebased(from origin: CLLocationCoordinate2D) -> Cafe {
        Cafe(
            id: id,
            name: name,
            address: address,
            roadAddress: roadAddress,
            phone: phone,
            categoryName: categoryName,
            placeURL: placeURL,
            coordinate: coordinate,
            distanceMeters: GeoMath.distanceMeters(from: origin, to: coordinate),
            bearingDegrees: GeoMath.bearingDegrees(from: origin, to: coordinate),
            tags: tags,
            source: source
        )
    }
}
