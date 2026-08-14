import SwiftUI

struct CategorySettingsView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsHeader
                    categoryGrid
                    infoPanel
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("빠른 탐색 카테고리")
                .font(.title3.weight(.bold))
            Text("자주 찾는 장소만 켜두면 지도와 하단 카드가 더 가볍게 정리됩니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(PlaceCategory.quickCategories) { category in
                categoryTile(category)
            }
        }
    }

    private func categoryTile(_ category: PlaceCategory) -> some View {
        let isSelected = store.selectedCategories.contains(category)

        return Button {
            store.toggleCategory(category)
            Task {
                await store.refreshPlaces(from: locationService.currentLocation, force: true)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isSelected ? .white : category.tint)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? category.tint : category.tint.opacity(0.14))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(isSelected ? "지도에 표시 중" : "숨김")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? category.tint : .secondary.opacity(0.55))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? category.tint.opacity(0.35) : .black.opacity(0.05), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var infoPanel: some View {
        VStack(spacing: 10) {
            InfoRow(
                icon: "battery.75percent",
                title: "위치 모드",
                value: "배터리 절약",
                description: "의미 있는 이동이 있을 때 주변 장소를 새로고침합니다."
            )

            Divider()

            InfoRow(
                icon: "map.fill",
                title: "지도",
                value: "Apple Map",
                description: "주변 장소 검색과 도보 경로를 제공합니다."
            )
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CategorySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CategorySettingsView()
            .environmentObject(LocationService.preview)
            .environmentObject(FastMapStore.preview)
    }
}
