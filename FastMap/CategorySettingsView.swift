import SwiftUI

struct CategorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PlaceCategory.quickCategories) { category in
                        categoryRow(category)
                    }
                } header: {
                    Text("빠른 탐색 카테고리")
                } footer: {
                    Text("선택한 장소만 지도와 주변 장소 목록에 표시됩니다.")
                }

                Section("FastMap") {
                    InfoRow(
                        icon: "battery.75percent",
                        title: "위치 모드",
                        value: "배터리 절약",
                        tint: .green
                    )

                    InfoRow(
                        icon: "map.fill",
                        title: "지도 및 도보 경로",
                        value: "Apple 지도",
                        tint: .blue
                    )

                    InfoRow(
                        icon: "location.fill.viewfinder",
                        title: "잠금 화면 안내",
                        value: "Live Activity",
                        tint: .indigo
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("FastMap 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func categoryRow(_ category: PlaceCategory) -> some View {
        let isSelected = store.selectedCategories.contains(category)

        return HStack(spacing: 12) {
            Image(systemName: category.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(category.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(category.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(category.title, isOn: Binding(
                get: { isSelected },
                set: { _ in
                    store.toggleCategory(category)
                    Task {
                        await store.refreshPlaces(from: locationService.currentLocation, force: true)
                    }
                }
            ))
            .labelsHidden()
            .tint(category.tint)
            .fixedSize()
        }
        .padding(.vertical, 3)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .padding(.vertical, 3)
        .frame(minHeight: 44)
    }
}

struct CategorySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CategorySettingsView()
            .environmentObject(LocationService.preview)
            .environmentObject(FastMapStore.preview)
    }
}
