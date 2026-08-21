//
//  CategorySettingsView.swift
//  FastMap
//
//  카테고리 관리 화면. 추가·편집·삭제·정렬을 모두 여기서 합니다.
//
//  List의 편집 모드(EditMode)는 행 양옆에 삭제 버튼과 정렬 손잡이를 끼워 넣으면서
//  카드 배경과 콘텐츠 정렬을 밀어냅니다. 그래서 ScrollView + 직접 만든 드래그 정렬을 씁니다.
//

import SwiftUI

struct CategorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore
    @EnvironmentObject private var categoryStore: CategoryStore

    /// 드래그 정렬 중에만 쓰는 임시 순서. 손을 떼면 스토어에 반영합니다.
    @State private var rows: [PlaceCategory] = []
    @State private var draggingID: String?
    @State private var dragTranslation: CGFloat = 0
    /// 이미 자리바꿈에 반영한 칸 수.
    @State private var settledShift = 0
    /// 햅틱 트리거용 카운터.
    @State private var swapCount = 0

    @State private var editorMode: EditorPresentation?
    @State private var isShowingResetConfirm = false

    private let rowHeight: CGFloat = 66
    private let rowSpacing = TossSpacing.s

    private var slotHeight: CGFloat { rowHeight + rowSpacing }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TossSpacing.xxl) {
                    header
                    categorySection
                    restorableSection
                    resetSection
                }
                .padding(.horizontal, TossEdge.screenInset)
                .padding(.top, TossSpacing.xxs)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(draggingID != nil)
            .tossPageBackground()
            .safeAreaInset(edge: .bottom) { addBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                        .font(TossFont.headline)
                        .foregroundStyle(TossColor.textSecondary)
                }
            }
            .toolbarBackground(TossColor.background, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .sensoryFeedback(.impact(weight: .light), trigger: swapCount)
            .sheet(item: $editorMode) { presentation in
                CategoryEditorView(
                    mode: presentation.mode,
                    onSave: { category in
                        switch presentation.mode {
                        case .create: categoryStore.add(category)
                        case .edit: categoryStore.update(category)
                        }
                        syncRows()
                        refresh()
                    },
                    onDelete: { category in
                        categoryStore.remove(category)
                        syncRows()
                        refresh()
                    }
                )
                .environmentObject(categoryStore)
                .environmentObject(locationService)
                .presentationCornerRadius(TossRadius.sheet)
            }
            .confirmationDialog(
                "카테고리를 처음 상태로 되돌릴까요?",
                isPresented: $isShowingResetConfirm,
                titleVisibility: .visible
            ) {
                Button("기본만 초기화 (내가 만든 건 유지)") {
                    categoryStore.resetAll(keepingCustomCategories: true)
                    syncRows()
                    refresh()
                }
                Button("전부 초기화", role: .destructive) {
                    categoryStore.resetAll(keepingCustomCategories: false)
                    syncRows()
                    refresh()
                }
                Button("취소", role: .cancel) {}
            }
            .onAppear(perform: syncRows)
            .onChange(of: categoryStore.categories) { _, _ in
                guard draggingID == nil else { return }
                syncRows()
            }
        }
    }

    // MARK: - 구역

    private var header: some View {
        VStack(alignment: .leading, spacing: TossSpacing.xxs) {
            Text("카테고리")
                .font(TossFont.display)
                .foregroundStyle(TossColor.textPrimary)

            Text("이름만 적으면 검색 방식은 알아서 정해 드려요.")
                .font(TossFont.callout)
                .foregroundStyle(TossColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, TossSpacing.xs)
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            TossSectionHeader(
                title: "표시 중인 카테고리",
                trailing: "\(categoryStore.activeCategories.count)개 탐색 중"
            )

            LazyVStack(spacing: rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, category in
                    categoryRow(category, index: index)
                }
            }

            Text("손잡이를 잡고 위아래로 끌면 순서가 바뀌어요. 길게 누르면 삭제할 수 있어요.")
                .font(TossFont.footnote)
                .foregroundStyle(TossColor.textTertiary)
                .padding(.horizontal, TossSpacing.xxs)
        }
    }

    @ViewBuilder
    private var restorableSection: some View {
        let restorable = categoryStore.restorableBuiltIns

        if !restorable.isEmpty {
            VStack(alignment: .leading, spacing: TossSpacing.m) {
                TossSectionHeader(title: "되돌릴 수 있는 카테고리")

                VStack(spacing: 0) {
                    ForEach(Array(restorable.enumerated()), id: \.element.id) { index, category in
                        HStack(spacing: TossSpacing.m) {
                            TossIconBadge(systemName: category.symbolName, tint: TossColor.textTertiary, size: 36)

                            Text(category.title)
                                .font(TossFont.bodyStrong)
                                .foregroundStyle(TossColor.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("되돌리기") {
                                categoryStore.restoreBuiltIn(id: category.id)
                                syncRows()
                                refresh()
                            }
                            .font(TossFont.buttonSmall)
                            .foregroundStyle(TossColor.blue)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, TossSpacing.l)
                        .frame(height: 60)

                        if index < restorable.count - 1 {
                            TossDivider(leadingInset: 64)
                        }
                    }
                }
                .padding(.vertical, TossSpacing.xxs)
                .tossCard()

                Text("삭제한 기본 카테고리예요. 같은 이름으로 새로 만들어도 되고, 여기서 되돌려도 돼요.")
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textTertiary)
                    .padding(.horizontal, TossSpacing.xxs)
            }
        }
    }

    private var resetSection: some View {
        Button("카테고리 초기화") {
            isShowingResetConfirm = true
        }
        .buttonStyle(
            TossSecondaryButtonStyle(
                height: TossSize.controlHeight,
                foreground: TossColor.red,
                background: TossColor.redWeak
            )
        )
    }

    // MARK: - 행

    private func categoryRow(_ category: PlaceCategory, index: Int) -> some View {
        let isDragging = draggingID == category.id

        return HStack(spacing: TossSpacing.s) {
            Button {
                editorMode = EditorPresentation(mode: .edit(category))
            } label: {
                HStack(spacing: TossSpacing.m) {
                    TossIconBadge(systemName: category.symbolName, tint: category.tint, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(TossFont.bodyStrong)
                            .foregroundStyle(TossColor.textPrimary)
                            .lineLimit(1)

                        Text(subtitle(for: category))
                            .font(TossFont.footnote)
                            .foregroundStyle(TossColor.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(category.title, isOn: Binding(
                get: { categoryStore.isEnabled(category) },
                set: { newValue in
                    categoryStore.setEnabled(newValue, for: category)
                    refresh()
                }
            ))
            .labelsHidden()
            .tint(TossColor.blue)
            .fixedSize()

            reorderGrip(for: category, index: index)
        }
        .padding(.leading, TossSpacing.l)
        .padding(.trailing, TossSpacing.xxs)
        .frame(height: rowHeight)
        .tossCard(shadow: isDragging ? .floating : .card)
        .scaleEffect(isDragging ? 1.02 : 1)
        .offset(y: isDragging ? dragTranslation - CGFloat(settledShift) * slotHeight : 0)
        .zIndex(isDragging ? 1 : 0)
        // 끌고 있는 카드는 손가락을 그대로 따라가야 하므로 애니메이션을 끕니다.
        // 자리를 내주는 다른 카드들만 부드럽게 움직입니다.
        .transaction { transaction in
            if isDragging { transaction.animation = nil }
        }
        .contextMenu {
            Button("이 카테고리 삭제", role: .destructive) {
                categoryStore.remove(category)
                syncRows()
                refresh()
            }
        }
    }

    /// 이 손잡이를 잡고 끌면 순서가 바뀝니다.
    private func reorderGrip(for category: PlaceCategory, index: Int) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(draggingID == category.id ? TossColor.blue : TossColor.textTertiary)
            .frame(width: 34, height: rowHeight)
            .contentShape(Rectangle())
            .gesture(reorderGesture(for: category, startIndex: index))
            .accessibilityLabel("\(category.title) 순서 변경")
    }

    private func reorderGesture(for category: PlaceCategory, startIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if draggingID == nil {
                    draggingID = category.id
                    settledShift = 0
                }
                dragTranslation = value.translation.height
                applyLiveReorder(for: category)
            }
            .onEnded { _ in
                withAnimation(TossMotion.quick) {
                    draggingID = nil
                    dragTranslation = 0
                    settledShift = 0
                }
                categoryStore.applyOrder(rows)
            }
    }

    /// 드래그한 칸 수만큼 실제 배열을 옮깁니다.
    private func applyLiveReorder(for category: PlaceCategory) {
        let shift = Int((dragTranslation / slotHeight).rounded())
        guard shift != settledShift,
              let currentIndex = rows.firstIndex(where: { $0.id == category.id }) else { return }

        // 목록 끝에서는 요청한 만큼 못 옮길 수 있습니다.
        // 실제로 옮겨진 칸 수만 누적해야 카드 위치 보정이 어긋나지 않습니다.
        let target = min(rows.count - 1, max(0, currentIndex + (shift - settledShift)))
        guard target != currentIndex else { return }

        withAnimation(TossMotion.quick) {
            let moved = rows.remove(at: currentIndex)
            rows.insert(moved, at: target)
            settledShift += target - currentIndex
        }
        swapCount += 1
    }

    // MARK: - 하단 버튼

    private var addBar: some View {
        Button {
            editorMode = EditorPresentation(mode: .create)
        } label: {
            Label("카테고리 추가", systemImage: "plus")
        }
        .buttonStyle(TossPrimaryButtonStyle())
        .padding(.horizontal, TossEdge.screenInset)
        .padding(.top, TossSpacing.m)
        .padding(.bottom, TossSpacing.s)
        .background {
            Rectangle()
                .fill(TossColor.background)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - 보조

    private func subtitle(for category: PlaceCategory) -> String {
        var parts: [String] = []
        if !category.isBuiltIn { parts.append("내가 만든 카테고리") }
        if category.poiRawValues.isEmpty {
            parts.append("‘\(category.searchQuery)’ 검색")
        } else {
            let names = category.poiRawValues.compactMap(POICatalog.displayName(forRawValue:))
            parts.append(names.isEmpty ? "지도 분류 검색" : names.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private func syncRows() {
        rows = categoryStore.visibleCategories
    }

    private func refresh() {
        Task {
            await store.refreshPlaces(
                from: locationService.currentLocation,
                categories: categoryStore.activeCategories,
                force: true
            )
        }
    }
}

// MARK: - 시트 표현

private struct EditorPresentation: Identifiable {
    let id = UUID()
    let mode: CategoryEditorView.Mode
}

struct CategorySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CategorySettingsView()
            .environmentObject(LocationService.preview)
            .environmentObject(FastMapStore.preview)
            .environmentObject(CategoryStore.preview)
    }
}
