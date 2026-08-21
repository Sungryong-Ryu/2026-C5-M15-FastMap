import AuthenticationServices
import CoreLocation
import SwiftUI

struct AccountCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var savedPlacesStore: SavedPlacesStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var isShowingProfileEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TossSpacing.xxl) {
                    profileCard

                    if accountManager.account != nil {
                        savedPlacesSection
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
            .tossPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("내 FastMap")
                        .font(TossFont.title3)
                        .foregroundStyle(TossColor.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                        .font(TossFont.headline)
                        .foregroundStyle(TossColor.textSecondary)
                }
            }
            .toolbarBackground(TossColor.background, for: .navigationBar)
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
            return savedPlacesStore.syncState.text
        }
        return "프로필을 눌러 사진이나 이모지로 꾸며 보세요"
    }

    // MARK: - 저장한 장소

    private var savedPlacesSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            TossSectionHeader(
                title: "저장한 장소",
                trailing: savedPlacesStore.places.isEmpty ? nil : "\(savedPlacesStore.places.count)곳"
            )

            VStack(spacing: 0) {
                if savedPlacesStore.places.isEmpty {
                    TossEmptyState(
                        systemImage: "bookmark",
                        title: "아직 저장한 장소가 없어요",
                        message: "장소 목록의 북마크 버튼을 눌러\n자주 가는 곳을 저장해 보세요."
                    )
                } else {
                    ForEach(Array(savedPlacesStore.places.enumerated()), id: \.element.id) { index, place in
                        savedPlaceRow(place)

                        if index < savedPlacesStore.places.count - 1 {
                            TossDivider(leadingInset: 68)
                        }
                    }
                }
            }
            .padding(.vertical, TossSpacing.xxs)
            .tossCard()
        }
    }

    private func savedPlaceRow(_ place: Place) -> some View {
        HStack(spacing: 0) {
            Button {
                let updatedPlace = place.rebased(from: locationService.currentLocation)
                Task {
                    await store.select(updatedPlace, from: locationService.currentLocation)
                    dismiss()
                }
            } label: {
                SavedPlaceRow(place: place)
            }
            .buttonStyle(TossPressableStyle(cornerRadius: TossRadius.field))

            Button {
                Task { await savedPlacesStore.remove(place) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(TossScaleButtonStyle())
            .accessibilityLabel("\(place.name) 저장 취소")
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

            Text("로그아웃해도 iCloud에 저장된 장소는 삭제되지 않아요.")
                .font(TossFont.footnote)
                .foregroundStyle(TossColor.textTertiary)
                .padding(.horizontal, TossSpacing.xxs)
        }
    }

    // MARK: - 로그인

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.l) {
            VStack(alignment: .leading, spacing: TossSpacing.s) {
                Text("자주 가는 곳,\n저장해 두세요")
                    .font(TossFont.title1)
                    .foregroundStyle(TossColor.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Apple 계정으로 로그인하면 장소를 저장하고\n같은 iCloud 계정의 기기에서 이어서 볼 수 있어요.")
                    .font(TossFont.body)
                    .foregroundStyle(TossColor.textSecondary)
                    .lineSpacing(3)
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

private struct SavedPlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: TossSpacing.m) {
            TossIconBadge(systemName: place.category.symbolName, tint: place.category.tint, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(TossFont.headline)
                    .foregroundStyle(TossColor.textPrimary)
                    .lineLimit(1)
                Text(place.address)
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

private extension Place {
    func rebased(from origin: CLLocationCoordinate2D) -> Place {
        Place(
            id: id,
            name: name,
            category: category,
            address: address,
            coordinate: coordinate,
            distanceMeters: GeoMath.distanceMeters(from: origin, to: coordinate),
            bearingDegrees: GeoMath.bearingDegrees(from: origin, to: coordinate)
        )
    }
}
