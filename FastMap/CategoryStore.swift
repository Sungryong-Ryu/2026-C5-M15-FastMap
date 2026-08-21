//
//  CategoryStore.swift
//  FastMap
//
//  카테고리 목록의 단일 소스. 순서, 활성화 여부, 아이콘/색/이름 편집, 사용자 추가 카테고리를
//  모두 여기서 관리하고 UserDefaults에 저장합니다.
//
//  삭제는 "진짜 삭제"입니다. 기본 카테고리를 지우면 목록에서 사라지고,
//  같은 이름으로 새 카테고리를 만들 수 있습니다. 지운 기본 카테고리는
//  설정 화면의 "되돌리기" 섹션에서 다시 추가할 수 있습니다.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class CategoryStore: ObservableObject {
    /// 사용자가 정한 순서대로 유지되는 전체 카테고리.
    @Published private(set) var categories: [PlaceCategory] = []
    /// 현재 탐색에 사용 중인 카테고리 id.
    @Published private(set) var enabledIDs: Set<String> = []
    /// 사용자가 삭제한 기본 카테고리 id. 앱을 다시 켜도 되살아나지 않게 기억합니다.
    @Published private(set) var removedBuiltInIDs: Set<String> = []

    private let defaults: UserDefaults
    private let categoriesKey = "fastmap.categories.v1"
    private let enabledKey = "fastmap.categories.enabled.v1"
    private let removedKey = "fastmap.categories.removedBuiltIn.v1"
    private var isLoading = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Derived

    /// 칩 목록에 노출되는 카테고리.
    var visibleCategories: [PlaceCategory] { categories }

    /// 실제로 주변 검색에 사용할 카테고리.
    var activeCategories: [PlaceCategory] {
        categories.filter { enabledIDs.contains($0.id) }
    }

    var customCategories: [PlaceCategory] {
        categories.filter { !$0.isBuiltIn }
    }

    /// 삭제되어 되돌릴 수 있는 기본 카테고리.
    var restorableBuiltIns: [PlaceCategory] {
        PlaceCategory.builtInDefaults.filter { removedBuiltInIDs.contains($0.id) }
    }

    func isEnabled(_ category: PlaceCategory) -> Bool {
        enabledIDs.contains(category.id)
    }

    func category(withID id: String) -> PlaceCategory? {
        categories.first { $0.id == id }
    }

    /// 현재 목록에 같은 이름이 있는지 확인합니다.
    /// 삭제된 카테고리는 목록에 없으므로 같은 이름을 다시 쓸 수 있습니다.
    func containsTitle(_ title: String, excluding id: String? = nil) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return categories.contains { $0.id != id && $0.title.lowercased() == normalized }
    }

    // MARK: - Mutations

    func toggle(_ category: PlaceCategory) {
        if enabledIDs.contains(category.id) {
            enabledIDs.remove(category.id)
        } else {
            enabledIDs.insert(category.id)
        }
        persist()
    }

    func setEnabled(_ isEnabled: Bool, for category: PlaceCategory) {
        if isEnabled {
            enabledIDs.insert(category.id)
        } else {
            enabledIDs.remove(category.id)
        }
        persist()
    }

    func add(_ category: PlaceCategory, enabled: Bool = true) {
        guard !categories.contains(where: { $0.id == category.id }) else {
            update(category)
            return
        }
        categories.append(category)
        removedBuiltInIDs.remove(category.id)
        if enabled {
            enabledIDs.insert(category.id)
        }
        persist()
    }

    func update(_ category: PlaceCategory) {
        guard let index = categories.firstIndex(of: category) else { return }
        categories[index] = category
        persist()
    }

    /// 카테고리를 목록에서 완전히 제거합니다.
    /// 기본 카테고리였다면 나중에 되돌릴 수 있도록 id만 기억해 둡니다.
    func remove(_ category: PlaceCategory) {
        categories.removeAll { $0.id == category.id }
        enabledIDs.remove(category.id)
        if category.isBuiltIn, PlaceCategory.builtIn(id: category.id) != nil {
            removedBuiltInIDs.insert(category.id)
        }
        persist()
    }

    /// 삭제했던 기본 카테고리를 출고 상태로 다시 추가합니다.
    func restoreBuiltIn(id: String) {
        guard let original = PlaceCategory.builtIn(id: id) else { return }
        removedBuiltInIDs.remove(id)
        if let index = categories.firstIndex(where: { $0.id == id }) {
            categories[index] = original
        } else {
            categories.append(original)
        }
        enabledIDs.insert(id)
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// 화면에서 계산한 전체 순서를 그대로 반영합니다.
    func applyOrder(_ ordered: [PlaceCategory]) {
        guard Set(ordered.map(\.id)) == Set(categories.map(\.id)) else { return }
        categories = ordered
        persist()
    }

    /// 기본 카테고리의 이름·아이콘·색을 출고 상태로 되돌립니다.
    func resetToDefault(_ category: PlaceCategory) {
        guard let original = PlaceCategory.builtIn(id: category.id),
              let index = categories.firstIndex(of: category) else { return }
        categories[index] = original
        persist()
    }

    /// 전체를 초기 상태로 되돌립니다. 사용자가 만든 카테고리는 유지할지 선택할 수 있습니다.
    func resetAll(keepingCustomCategories keepCustom: Bool = true) {
        let custom = keepCustom ? customCategories : []
        categories = PlaceCategory.builtInDefaults + custom
        removedBuiltInIDs = []
        enabledIDs = Set(CategoryStore.defaultEnabledIDs)
        persist()
    }

    // MARK: - Persistence

    private static let defaultEnabledIDs = ["restroom", "cafe", "bank"]

    private func load() {
        isLoading = true
        defer { isLoading = false }

        removedBuiltInIDs = Set(defaults.array(forKey: removedKey) as? [String] ?? [])

        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: categoriesKey),
           let stored = try? decoder.decode([PlaceCategory].self, from: data) {
            categories = merged(stored: stored)
        } else {
            categories = PlaceCategory.builtInDefaults
        }

        if let storedEnabled = defaults.array(forKey: enabledKey) as? [String] {
            enabledIDs = Set(storedEnabled)
        } else {
            enabledIDs = Set(CategoryStore.defaultEnabledIDs)
        }

        enabledIDs.formIntersection(Set(categories.map(\.id)))
        if enabledIDs.isEmpty, let first = categories.first {
            enabledIDs = [first.id]
        }
    }

    /// 저장된 목록을 정리합니다.
    /// - 예전 버전에서 "숨김"으로 지운 기본 카테고리는 삭제 목록으로 옮깁니다.
    /// - 앱 업데이트로 새 기본 카테고리가 생기면, 지운 적 없는 것만 뒤에 붙입니다.
    private func merged(stored: [PlaceCategory]) -> [PlaceCategory] {
        var result: [PlaceCategory] = []

        for var category in stored {
            if category.isHidden {
                // 구버전 마이그레이션: 숨김 = 삭제로 취급합니다.
                if category.isBuiltIn, PlaceCategory.builtIn(id: category.id) != nil {
                    removedBuiltInIDs.insert(category.id)
                }
                continue
            }
            category.isHidden = false
            result.append(category)
        }

        let existingIDs = Set(result.map(\.id))
        for builtIn in PlaceCategory.builtInDefaults
        where !existingIDs.contains(builtIn.id) && !removedBuiltInIDs.contains(builtIn.id) {
            result.append(builtIn)
        }

        return result
    }

    private func persist() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(categories) {
            defaults.set(data, forKey: categoriesKey)
        }
        defaults.set(Array(enabledIDs), forKey: enabledKey)
        defaults.set(Array(removedBuiltInIDs), forKey: removedKey)
    }

    // MARK: - Preview

    static var preview: CategoryStore {
        let store = CategoryStore(defaults: UserDefaults(suiteName: "fastmap.preview") ?? .standard)
        store.categories = PlaceCategory.builtInDefaults
        store.enabledIDs = ["restroom", "cafe", "bank"]
        return store
    }
}
