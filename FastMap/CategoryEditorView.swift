//
//  CategoryEditorView.swift
//  FastMap
//
//  카테고리 추가/편집 화면. 이름을 입력하면 Apple Intelligence(또는 키워드 분석)가
//  검색어·지도 분류·아이콘·색을 채워 주고, 사용자가 그 값을 그대로 덮어쓸 수 있습니다.
//

import SwiftUI

struct CategoryEditorView: View {
    enum Mode {
        case create
        case edit(PlaceCategory)
    }

    let mode: Mode
    let onSave: (PlaceCategory) -> Void
    var onDelete: ((PlaceCategory) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var intelligence = CategoryIntelligence()

    @State private var title = ""
    @State private var symbolName = "mappin.circle.fill"
    @State private var colorID = CategoryPalette.fallbackID
    @State private var searchQuery = ""
    @State private var poiRawValues: [String] = []
    @State private var analysisNote: String?
    @State private var isAnalyzing = false
    @State private var hasAnalyzedOnce = false
    @State private var isShowingSymbolPicker = false
    @State private var isShowingAdvanced = false
    @State private var analyzedTitle = ""
    @State private var previewState: NearbyPreviewState = .idle
    @State private var analysisTask: Task<Void, Never>?
    @State private var isSaving = false
    @FocusState private var isTitleFocused: Bool

    /// 이 카테고리로 주변을 찾아봤을 때의 결과. 저장 전에 미리 확인시켜 줍니다.
    enum NearbyPreviewState: Equatable {
        case idle
        case searching
        case found(Int)
        case empty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TossSpacing.xxl) {
                    previewCard
                    nameSection
                    appearanceSection
                    advancedSection

                    if case .edit(let category) = mode {
                        deleteButton(category)
                    }
                }
                .padding(.horizontal, TossEdge.screenInset)
                .padding(.top, TossSpacing.s)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .tossPageBackground()
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isCreating ? "카테고리 추가" : "카테고리 편집")
                        .font(TossFont.title3)
                        .foregroundStyle(TossColor.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .font(TossFont.headline)
                        .foregroundStyle(TossColor.textSecondary)
                }
            }
            .toolbarBackground(TossColor.background, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .sheet(isPresented: $isShowingSymbolPicker) {
                SymbolPickerView(selection: $symbolName, tint: CategoryPalette.color(for: colorID))
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(TossRadius.sheet)
            }
            .onAppear(perform: prepare)
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && !isDuplicateTitle
    }

    private var isDuplicateTitle: Bool {
        guard !trimmedTitle.isEmpty else { return false }
        let excludedID: String?
        if case .edit(let category) = mode { excludedID = category.id } else { excludedID = nil }
        return categoryStore.containsTitle(trimmedTitle, excluding: excludedID)
    }

    // MARK: - Preview

    private var previewCard: some View {
        HStack(spacing: TossSpacing.l) {
            TossIconBadge(
                systemName: symbolName,
                tint: CategoryPalette.color(for: colorID),
                size: 56
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(trimmedTitle.isEmpty ? "새 카테고리" : trimmedTitle)
                    .font(TossFont.title2)
                    .foregroundStyle(trimmedTitle.isEmpty ? TossColor.textTertiary : TossColor.textPrimary)
                    .lineLimit(1)

                Text(searchQuery.isEmpty ? "이름을 입력해 주세요" : "‘\(searchQuery)’ 로 검색")
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TossSpacing.l)
        .tossCard()
    }

    // MARK: - Name + analysis

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            TossSectionHeader(title: "카테고리 이름")

            TextField("예: 코인 세탁방, 무인 카페, 강아지 병원", text: $title)
                .font(TossFont.body)
                .foregroundStyle(TossColor.textPrimary)
                .tint(TossColor.blue)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit {
                    isTitleFocused = false
                    runAnalysis(force: true)
                }
                .onChange(of: title) { _, newValue in
                    scheduleAnalysis(for: newValue)
                }
                .padding(.horizontal, TossSpacing.l)
                .frame(height: TossSize.fieldHeight)
                .background(TossColor.surfaceAlt, in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))

            if isDuplicateTitle {
                Label("같은 이름의 카테고리가 이미 있어요.", systemImage: "exclamationmark.circle.fill")
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.red)
            }

            analysisPanel
        }
    }

    private var analysisPanel: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            HStack(spacing: TossSpacing.m) {
                TossIconBadge(
                    systemName: intelligence.isAppleIntelligenceAvailable ? "sparkles" : "text.magnifyingglass",
                    tint: intelligence.isAppleIntelligenceAvailable ? TossColor.blue : TossColor.textSecondary,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(intelligence.isAppleIntelligenceAvailable ? "Apple Intelligence 자동 분석" : "키워드 자동 분석")
                        .font(TossFont.bodyStrong)
                        .foregroundStyle(TossColor.textPrimary)

                    Text(analysisNote ?? intelligence.unavailableReason ?? "이름을 입력하면 검색 방식을 알아서 정해 드려요.")
                        .font(TossFont.footnote)
                        .foregroundStyle(TossColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(TossColor.blue)
                }
            }

            previewRow

            Button {
                isTitleFocused = false
                runAnalysis(force: true)
            } label: {
                Text(hasAnalyzedOnce ? "다시 분석하기" : "이름으로 분석하기")
            }
            .buttonStyle(TossTonalButtonStyle(height: TossSize.controlHeight))
            .disabled(trimmedTitle.isEmpty || isAnalyzing)
        }
        .padding(TossSpacing.l)
        .tossCard()
    }

    /// 지금 설정으로 주변을 찾으면 몇 곳이 나오는지 보여 줍니다.
    @ViewBuilder
    private var previewRow: some View {
        switch previewState {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: TossSpacing.s) {
                ProgressView()
                    .controlSize(.small)
                    .tint(TossColor.textTertiary)
                Text("주변에서 찾아보는 중")
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TossSpacing.m)
            .frame(height: 40)
            .background(TossColor.surfaceAlt, in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))
        case .found(let count):
            Label("지금 내 주변에서 \(count)곳 찾았어요", systemImage: "checkmark.circle.fill")
                .font(TossFont.captionStrong)
                .foregroundStyle(TossColor.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TossSpacing.m)
                .frame(height: 40)
                .background(TossColor.surfaceAlt, in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))
        case .empty:
            VStack(alignment: .leading, spacing: TossSpacing.xxs) {
                Label("주변에서 찾지 못했어요", systemImage: "exclamationmark.circle.fill")
                    .font(TossFont.captionStrong)
                    .foregroundStyle(TossColor.yellow)
                Text("‘검색 방식 직접 설정’에서 검색어를 더 일반적인 말로 바꿔 보세요.")
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TossSpacing.m)
            .background(TossColor.surfaceAlt, in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            TossSectionHeader(title: "아이콘과 색")

            VStack(spacing: 0) {
                Button {
                    isShowingSymbolPicker = true
                } label: {
                    HStack(spacing: TossSpacing.m) {
                        TossIconBadge(systemName: symbolName, tint: CategoryPalette.color(for: colorID), size: 36)
                        Text("아이콘")
                            .font(TossFont.bodyStrong)
                            .foregroundStyle(TossColor.textPrimary)
                        Spacer()
                        Text(symbolName)
                            .font(TossFont.footnote)
                            .foregroundStyle(TossColor.textTertiary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TossColor.textTertiary)
                    }
                    .padding(.horizontal, TossSpacing.l)
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TossPressableStyle())

                TossDivider(leadingInset: TossSpacing.l)

                VStack(alignment: .leading, spacing: TossSpacing.m) {
                    Text("색")
                        .font(TossFont.bodyStrong)
                        .foregroundStyle(TossColor.textPrimary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TossSpacing.m) {
                            ForEach(CategoryPalette.options) { option in
                                Button {
                                    colorID = option.id
                                } label: {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 34, height: 34)
                                        .overlay {
                                            if colorID == option.id {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .overlay {
                                            Circle()
                                                .strokeBorder(TossColor.textPrimary.opacity(colorID == option.id ? 0.25 : 0), lineWidth: 2)
                                        }
                                }
                                .buttonStyle(TossScaleButtonStyle())
                                .accessibilityLabel(option.title)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, TossSpacing.l)
                .padding(.vertical, TossSpacing.l)
            }
            .tossCard()
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            Button {
                withAnimation(TossMotion.snappy) { isShowingAdvanced.toggle() }
            } label: {
                HStack {
                    Text("검색 방식 직접 설정")
                        .font(TossFont.title3)
                        .foregroundStyle(TossColor.textPrimary)
                    Spacer()
                    Image(systemName: isShowingAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TossColor.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isShowingAdvanced {
                VStack(alignment: .leading, spacing: TossSpacing.l) {
                    VStack(alignment: .leading, spacing: TossSpacing.s) {
                        Text("지도 검색어")
                            .font(TossFont.captionStrong)
                            .foregroundStyle(TossColor.textSecondary)

                        TextField("예: 코인 세탁", text: $searchQuery)
                            .font(TossFont.body)
                            .tint(TossColor.blue)
                            .padding(.horizontal, TossSpacing.m)
                            .frame(height: 44)
                            .background(TossColor.surfaceAlt, in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: TossSpacing.s) {
                        Text("Apple 지도 분류")
                            .font(TossFont.captionStrong)
                            .foregroundStyle(TossColor.textSecondary)

                        Text(poiRawValues.isEmpty
                             ? "선택된 분류가 없어요. 검색어로만 찾습니다."
                             : poiRawValues.compactMap(POICatalog.displayName(forRawValue:)).joined(separator: ", "))
                            .font(TossFont.footnote)
                            .foregroundStyle(TossColor.textTertiary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: TossSpacing.s) {
                                ForEach(POICatalog.entries) { entry in
                                    let raw = entry.rawValue
                                    TossChip(
                                        title: entry.korean,
                                        isSelected: poiRawValues.contains(raw)
                                    ) {
                                        if let index = poiRawValues.firstIndex(of: raw) {
                                            poiRawValues.remove(at: index)
                                        } else {
                                            poiRawValues.append(raw)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(TossSpacing.l)
                .tossCard()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func deleteButton(_ category: PlaceCategory) -> some View {
        VStack(alignment: .leading, spacing: TossSpacing.s) {
            Button("이 카테고리 삭제") {
                onDelete?(category)
                dismiss()
            }
            .buttonStyle(
                TossSecondaryButtonStyle(
                    foreground: TossColor.red,
                    background: TossColor.redWeak
                )
            )

            if category.isBuiltIn {
                Text("기본 카테고리는 지워도 설정에서 다시 되돌릴 수 있어요.")
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textTertiary)
                    .padding(.horizontal, TossSpacing.xxs)
            }
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        Button {
            save()
        } label: {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Text(isCreating ? "카테고리 추가" : "저장")
            }
        }
        .buttonStyle(TossPrimaryButtonStyle())
        .disabled(!canSave || isSaving)
        .padding(.horizontal, TossEdge.screenInset)
        .padding(.top, TossSpacing.m)
        .padding(.bottom, TossSpacing.s)
        .background {
            Rectangle()
                .fill(TossColor.background)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Actions

    private func prepare() {
        guard case .edit(let category) = mode else {
            isTitleFocused = true
            return
        }
        guard title.isEmpty else { return }

        // analyzedTitle을 먼저 세팅해야 아래 title 대입이 자동 분석을 트리거하지 않습니다.
        analyzedTitle = category.title
        title = category.title
        symbolName = category.symbolName
        colorID = category.colorID
        searchQuery = category.searchQuery
        poiRawValues = category.poiRawValues
        hasAnalyzedOnce = true

        // 기존 카테고리가 실제로 장소를 찾아내는지 바로 보여 줍니다.
        Task { await runPreviewSearch() }
    }

    /// 이름을 입력하는 동안 잠깐 기다렸다가 자동으로 분석합니다.
    private func scheduleAnalysis(for name: String) {
        analysisTask?.cancel()
        previewState = .idle

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed != analyzedTitle else { return }

        analysisTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await performAnalysis(name: trimmed)
        }
    }

    private func runAnalysis(force: Bool) {
        let name = trimmedTitle
        guard !name.isEmpty, !isAnalyzing else { return }
        guard force || name != analyzedTitle else { return }

        analysisTask?.cancel()
        analysisTask = Task { await performAnalysis(name: name) }
    }

    private func performAnalysis(name: String, runsPreview: Bool = true) async {
        guard !name.isEmpty else { return }

        isAnalyzing = true
        let suggestion = await intelligence.analyze(name: name)

        guard !Task.isCancelled else {
            isAnalyzing = false
            return
        }

        analyzedTitle = name
        symbolName = suggestion.symbolName
        colorID = suggestion.colorID
        searchQuery = suggestion.searchQuery
        poiRawValues = suggestion.poiRawValues
        analysisNote = suggestion.explanation
        hasAnalyzedOnce = true
        isAnalyzing = false

        if runsPreview {
            await runPreviewSearch()
        }
    }

    /// 지금 설정 그대로 주변을 한 번 찾아봅니다.
    private func runPreviewSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            previewState = .idle
            return
        }

        previewState = .searching
        let probe = PlaceCategory(
            title: trimmedTitle.isEmpty ? query : trimmedTitle,
            symbolName: symbolName,
            colorID: colorID,
            searchQuery: query,
            poiRawValues: poiRawValues
        )
        let places = await NearbyPlaceService().searchPlaces(
            category: probe,
            around: locationService.currentLocation
        )

        guard !Task.isCancelled else { return }
        previewState = places.isEmpty ? .empty : .found(places.count)
    }

    private func save() {
        let name = trimmedTitle
        guard !name.isEmpty, !isSaving else { return }

        isSaving = true
        Task {
            // 사용자가 이름만 쓰고 바로 저장하는 경우가 많습니다.
            // 아직 분석되지 않은 이름이면 저장 직전에 분석을 끝내고 값을 채웁니다.
            if name != analyzedTitle {
                analysisTask?.cancel()
                await performAnalysis(name: name, runsPreview: false)
            }

            commit(name: name)
            isSaving = false
            dismiss()
        }
    }

    private func commit(name: String) {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var category: PlaceCategory

        switch mode {
        case .create:
            category = PlaceCategory(
                title: name,
                symbolName: CategorySymbolCatalog.validated(symbolName),
                colorID: colorID,
                searchQuery: query.isEmpty ? name : query,
                poiRawValues: poiRawValues,
                isBuiltIn: false
            )
        case .edit(let existing):
            category = existing
            category.title = name
            category.symbolName = CategorySymbolCatalog.validated(symbolName)
            category.colorID = colorID
            category.searchQuery = query.isEmpty ? name : query
            category.poiRawValues = poiRawValues
            category.isHidden = false
        }

        onSave(category)
    }
}

// MARK: - 아이콘 선택

struct SymbolPickerView: View {
    @Binding var selection: String
    let tint: Color

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: TossSpacing.m), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TossSpacing.xxl) {
                    ForEach(filteredGroups) { group in
                        VStack(alignment: .leading, spacing: TossSpacing.m) {
                            Text(group.title)
                                .font(TossFont.title3)
                                .foregroundStyle(TossColor.textPrimary)

                            LazyVGrid(columns: columns, spacing: TossSpacing.m) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    Button {
                                        selection = symbol
                                        dismiss()
                                    } label: {
                                        Image(systemName: symbol)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(selection == symbol ? Color.white : tint)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 56)
                                            .background(
                                                selection == symbol ? tint : TossColor.surfaceAlt,
                                                in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                                            )
                                    }
                                    .buttonStyle(TossScaleButtonStyle())
                                    .accessibilityLabel(symbol)
                                }
                            }
                        }
                    }

                    if filteredGroups.isEmpty {
                        TossEmptyState(
                            systemImage: "magnifyingglass",
                            title: "결과가 없어요",
                            message: "다른 이름으로 찾아보세요."
                        )
                    }
                }
                .padding(.horizontal, TossEdge.screenInset)
                .padding(.vertical, TossSpacing.l)
            }
            .scrollIndicators(.hidden)
            .tossPageBackground()
            .searchable(text: $query, prompt: "아이콘 이름 검색")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("아이콘 선택")
                        .font(TossFont.title3)
                        .foregroundStyle(TossColor.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                        .font(TossFont.headline)
                        .foregroundStyle(TossColor.blue)
                }
            }
            .toolbarBackground(TossColor.background, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
    }

    private var filteredGroups: [CategorySymbolCatalog.Group] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return CategorySymbolCatalog.groups }

        return CategorySymbolCatalog.groups.compactMap { group in
            let matches = group.symbols.filter { $0.lowercased().contains(trimmed) }
            guard !matches.isEmpty else { return nil }
            return CategorySymbolCatalog.Group(id: group.id, title: group.title, symbols: matches)
        }
    }
}
