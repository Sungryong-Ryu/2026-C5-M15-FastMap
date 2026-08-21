//
//  FastMapDesign.swift
//  FastMap
//
//  토스(Toss) 스타일 디자인 시스템 — 다크 모드 전용.
//  - 서피스는 색으로만 계단을 만들고, 경계는 헤어라인 한 줄로 처리합니다.
//    (다크 배경에서는 그림자가 거의 보이지 않아 오히려 지저분해집니다.)
//  - 토스 블루 + 뉴트럴 그레이
//  - 큰 볼드 타이틀 + 촘촘한 본문
//  - 꽉 찬 CTA 버튼 + 바텀시트
//

import SwiftUI
import UIKit

// MARK: - Color Primitives

private func tossColor(_ hex: UInt32) -> Color {
    Color(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255
    )
}

/// 다크 전용 팔레트. 서피스는 base → surface1 → surface2 → surface3 순으로 밝아집니다.
enum TossPalette {
    static let base: UInt32 = 0x0E1013
    static let surface1: UInt32 = 0x171A1F
    static let surface2: UInt32 = 0x1F242B
    static let surface3: UInt32 = 0x2A3038
    static let line: UInt32 = 0x252A32

    static let textPrimary: UInt32 = 0xF2F4F6
    static let textSecondary: UInt32 = 0x99A1AC
    static let textTertiary: UInt32 = 0x646C77

    static let blue: UInt32 = 0x4B93F8
    static let bluePressed: UInt32 = 0x3C7BD6
    static let blueWeak: UInt32 = 0x18273D

    static let red: UInt32 = 0xFF5A66
    static let redWeak: UInt32 = 0x2E1E21
    static let green: UInt32 = 0x2BD68F
    static let yellow: UInt32 = 0xFFC24B
}

/// 앱 전역에서 사용하는 시맨틱 컬러.
enum TossColor {
    /// 화면 전체 배경
    static let background = tossColor(TossPalette.base)
    /// 카드, 시트, 셀 등 올라온 서피스
    static let surface = tossColor(TossPalette.surface1)
    /// 서피스 위에 한 단계 더 올라온 요소 (검색바, 인풋, 칩)
    static let surfaceAlt = tossColor(TossPalette.surface2)
    /// 눌림 상태나 뉴트럴 필
    static let fill = tossColor(TossPalette.surface3)
    /// 구분선 · 카드 테두리
    static let separator = tossColor(TossPalette.line)
    /// 카드 테두리 전용 별칭
    static let line = tossColor(TossPalette.line)

    static let textPrimary = tossColor(TossPalette.textPrimary)
    static let textSecondary = tossColor(TossPalette.textSecondary)
    static let textTertiary = tossColor(TossPalette.textTertiary)
    static let textOnBlue = Color.white

    static let blue = tossColor(TossPalette.blue)
    static let bluePressed = tossColor(TossPalette.bluePressed)
    static let blueWeak = tossColor(TossPalette.blueWeak)

    static let red = tossColor(TossPalette.red)
    static let redWeak = tossColor(TossPalette.redWeak)
    static let green = tossColor(TossPalette.green)
    static let yellow = tossColor(TossPalette.yellow)

    /// 지도처럼 배경이 예측 불가한 곳에 얹는 서피스
    static let floatingSurface = tossColor(TossPalette.surface2)
}

/// 카테고리 마커/아이콘용 컬러. 어두운 배경 위에서 또렷하게 보이도록 밝기를 올린 계열.
/// 사용자가 카테고리 색을 직접 고를 수 있으므로 id로 조회합니다.
enum CategoryPalette {
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let color: Color
    }

    static let options: [Option] = [
        Option(id: "blue", title: "블루", color: TossColor.blue),
        Option(id: "violet", title: "바이올렛", color: tossColor(0x9A82F5)),
        Option(id: "teal", title: "틸", color: tossColor(0x2BC0C0)),
        Option(id: "green", title: "그린", color: tossColor(0x2BD68F)),
        Option(id: "lime", title: "라임", color: tossColor(0x8FCB3F)),
        Option(id: "yellow", title: "옐로", color: tossColor(0xFFC24B)),
        Option(id: "orange", title: "오렌지", color: tossColor(0xFF9A4D)),
        Option(id: "red", title: "레드", color: tossColor(0xFF6B76)),
        Option(id: "pink", title: "핑크", color: tossColor(0xF07AA8)),
        Option(id: "brown", title: "브라운", color: tossColor(0xC08F63)),
        Option(id: "navy", title: "네이비", color: tossColor(0x6E96E0)),
        Option(id: "gray", title: "그레이", color: tossColor(0x9BA3AF))
    ]

    static let fallbackID = "blue"

    static func color(for id: String) -> Color {
        options.first { $0.id == id }?.color ?? TossColor.blue
    }

    static func contains(_ id: String) -> Bool {
        options.contains { $0.id == id }
    }
}

/// 기존 코드 호환용 별칭.
enum TossCategoryColor {
    static var violet: Color { CategoryPalette.color(for: "violet") }
    static var teal: Color { CategoryPalette.color(for: "teal") }
    static var brown: Color { CategoryPalette.color(for: "brown") }
    static var navy: Color { CategoryPalette.color(for: "navy") }
    static var pink: Color { CategoryPalette.color(for: "pink") }
    static var green: Color { CategoryPalette.color(for: "green") }
    static var red: Color { CategoryPalette.color(for: "red") }
    static var orange: Color { CategoryPalette.color(for: "orange") }
}

// MARK: - Typography

/// 토스식 타이포 스케일. 타이틀은 굵고 크게, 본문은 촘촘하게.
enum TossFont {
    /// 화면 대표 타이틀
    static let display = Font.system(size: 28, weight: .bold)
    static let title1 = Font.system(size: 24, weight: .bold)
    static let title2 = Font.system(size: 20, weight: .bold)
    static let title3 = Font.system(size: 17, weight: .bold)

    static let headline = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let bodyStrong = Font.system(size: 15, weight: .semibold)
    static let callout = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 13, weight: .regular)
    static let captionStrong = Font.system(size: 13, weight: .semibold)
    static let footnote = Font.system(size: 12, weight: .medium)

    /// 버튼 라벨
    static let button = Font.system(size: 16, weight: .semibold)
    static let buttonSmall = Font.system(size: 14, weight: .semibold)
}

// MARK: - Metrics

enum TossRadius {
    static let chip: CGFloat = 999
    static let field: CGFloat = 12
    static let button: CGFloat = 14
    static let card: CGFloat = 18
    static let sheet: CGFloat = 24
    static let icon: CGFloat = 10
}

enum TossSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

enum TossSize {
    static let ctaHeight: CGFloat = 54
    static let controlHeight: CGFloat = 48
    static let compactControlHeight: CGFloat = 44
    static let chipHeight: CGFloat = 36
    static let fieldHeight: CGFloat = 50
    static let iconBadge: CGFloat = 40
}

enum TossMotion {
    static let snappy = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let quick = Animation.spring(response: 0.22, dampingFraction: 0.9)
}

// MARK: - Elevation

/// 다크 배경에서는 그림자가 거의 보이지 않습니다.
/// 카드는 헤어라인 한 줄로 경계를 잡고, 지도처럼 배경이 밝을 수 있는 곳에서만 그림자를 씁니다.
enum TossShadow {
    case none
    /// 카드 — 그림자 없이 헤어라인만
    case card
    /// 지도 위 떠 있는 컨트롤
    case floating
    /// 바텀시트
    case sheet
}

private struct TossShadowModifier: ViewModifier {
    let style: TossShadow

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .none, .card:
            content
        case .floating:
            content
                .shadow(color: .black.opacity(0.34), radius: 12, y: 4)
        case .sheet:
            content
                .shadow(color: .black.opacity(0.38), radius: 24, y: -6)
        }
    }
}

extension View {
    func tossShadow(_ style: TossShadow = .card) -> some View {
        modifier(TossShadowModifier(style: style))
    }
}

// MARK: - Surfaces

private struct TossCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let shadow: TossShadow
    let fill: Color
    let bordered: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(fill, in: shape)
            .overlay {
                if bordered {
                    shape.strokeBorder(TossColor.line, lineWidth: 1)
                }
            }
            .tossShadow(shadow)
    }
}

private struct TossSheetSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let extendsBelowSafeArea: Bool

    func body(content: Content) -> some View {
        content
            .background {
                let shape = ConcentricRectangle(
                    topLeadingCorner: .concentric(minimum: .fixed(cornerRadius)),
                    topTrailingCorner: .concentric(minimum: .fixed(cornerRadius)),
                    bottomLeadingCorner: extendsBelowSafeArea ? .concentric() : .concentric(minimum: .fixed(cornerRadius)),
                    bottomTrailingCorner: extendsBelowSafeArea ? .concentric() : .concentric(minimum: .fixed(cornerRadius))
                )

                shape
                    .fill(TossColor.surface)
                    .overlay { shape.stroke(TossColor.line, lineWidth: 1) }
                    .tossShadow(.sheet)
                    .ignoresSafeArea(edges: extendsBelowSafeArea ? Edge.Set.bottom : Edge.Set())
            }
    }
}

extension View {
    /// 한 단계 올라온 서피스 + 헤어라인.
    func tossCard(
        cornerRadius: CGFloat = TossRadius.card,
        shadow: TossShadow = .card,
        fill: Color = TossColor.surface,
        bordered: Bool = true
    ) -> some View {
        modifier(TossCardModifier(cornerRadius: cornerRadius, shadow: shadow, fill: fill, bordered: bordered))
    }

    /// 하단 바텀시트용 서피스. 화면 하단에 붙는 경우 안전 영역 아래까지 배경을 확장합니다.
    func tossSheetSurface(
        cornerRadius: CGFloat = TossRadius.sheet,
        extendsBelowSafeArea: Bool = true
    ) -> some View {
        modifier(TossSheetSurfaceModifier(cornerRadius: cornerRadius, extendsBelowSafeArea: extendsBelowSafeArea))
    }

    /// 화면 전체 배경.
    func tossPageBackground() -> some View {
        background(TossColor.background.ignoresSafeArea())
    }
}

// MARK: - Concentric corners

/// 아이폰 베젤 곡률을 고려한 여백/모서리 값.
///
/// 화면 가장자리에 붙는 요소는 모서리 곡률이 기기 베젤과 동심원을 이루지 않으면
/// 둥근 화면 모서리에 잘려 보입니다. iOS 26의 `ConcentricRectangle`을 쓰면
/// 컨테이너(기기 베젤)와의 거리만큼 반지름이 자동으로 줄어듭니다.
enum TossEdge {
    /// 화면 가장자리에 직접 붙는 콘텐츠의 최소 좌우 여백.
    /// 베젤 곡률 구간을 피하려면 12pt보다 넉넉해야 합니다.
    static let screenInset: CGFloat = 20
    /// 화면 하단 모서리 근처에 놓이는 요소의 추가 여백.
    static let bottomInset: CGFloat = 12
    /// 모서리 근처 플로팅 컨트롤에 필요한 여백.
    static let floatingInset: CGFloat = 20
}

private struct TossConcentricCardModifier: ViewModifier {
    let minimumRadius: CGFloat
    let shadow: TossShadow
    let fill: Color

    func body(content: Content) -> some View {
        content
            .background {
                let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(minimumRadius)), isUniform: true)

                shape
                    .fill(fill)
                    .overlay { shape.stroke(TossColor.line, lineWidth: 1) }
                    .tossShadow(shadow)
            }
    }
}

extension View {
    /// 화면 가장자리에 붙는 카드. 기기 베젤과 동심원을 이루도록 모서리가 자동 조정됩니다.
    func tossConcentricCard(
        minimumRadius: CGFloat = TossRadius.card,
        shadow: TossShadow = .card,
        fill: Color = TossColor.surface
    ) -> some View {
        modifier(TossConcentricCardModifier(minimumRadius: minimumRadius, shadow: shadow, fill: fill))
    }

    /// 컨테이너 모양을 지정해 내부의 동심원 모서리 계산 기준을 바꿉니다.
    func tossContainerShape(cornerRadius: CGFloat) -> some View {
        containerShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Buttons

/// 꽉 찬 토스 블루 CTA.
struct TossPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = TossSize.ctaHeight
    var cornerRadius: CGFloat = TossRadius.button
    var tint: Color = TossColor.blue

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, height: height, cornerRadius: cornerRadius, tint: tint)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        let cornerRadius: CGFloat
        let tint: Color

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(TossFont.button)
                .foregroundStyle(isEnabled ? TossColor.textOnBlue : TossColor.textTertiary)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(
                    isEnabled ? tint : TossColor.fill,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .opacity(configuration.isPressed ? 0.82 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(TossMotion.quick, value: configuration.isPressed)
        }
    }
}

/// 뉴트럴 배경 위 보조 버튼.
struct TossSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = TossSize.ctaHeight
    var cornerRadius: CGFloat = TossRadius.button
    var foreground: Color = TossColor.textPrimary
    var background: Color = TossColor.surfaceAlt

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TossFont.button)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(TossMotion.quick, value: configuration.isPressed)
    }
}

/// 옅은 블루 배경 + 블루 텍스트.
struct TossTonalButtonStyle: ButtonStyle {
    var height: CGFloat = TossSize.ctaHeight
    var cornerRadius: CGFloat = TossRadius.button

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TossFont.button)
            .foregroundStyle(TossColor.blue)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(TossColor.blueWeak, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(TossMotion.quick, value: configuration.isPressed)
    }
}

/// 눌림 피드백만 있는 투명 버튼 (리스트 행 등).
struct TossPressableStyle: ButtonStyle {
    var cornerRadius: CGFloat = TossRadius.field

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(TossColor.fill.opacity(configuration.isPressed ? 0.6 : 0))
            )
            .animation(TossMotion.quick, value: configuration.isPressed)
    }
}

// MARK: - Components

/// 둥근 사각 아이콘 배지.
struct TossIconBadge: View {
    let systemName: String
    var tint: Color = TossColor.blue
    var size: CGFloat = TossSize.iconBadge
    var style: Style = .tinted

    enum Style {
        /// 옅은 배경 + 컬러 아이콘
        case tinted
        /// 채워진 배경 + 흰 아이콘
        case filled
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(style == .filled ? Color.white : tint)
            .frame(width: size, height: size)
            .background(
                style == .filled ? tint : tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            )
    }
}

/// 토스식 캡슐 칩.
struct TossChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(TossFont.buttonSmall)
            }
            .foregroundStyle(isSelected ? TossColor.textOnBlue : TossColor.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: TossSize.chipHeight)
            .background(isSelected ? TossColor.blue : TossColor.surfaceAlt, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 섹션 타이틀 + 보조 텍스트.
struct TossSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TossFont.title3)
                .foregroundStyle(TossColor.textPrimary)
            Spacer(minLength: TossSpacing.s)
            if let trailing {
                Text(trailing)
                    .font(TossFont.caption)
                    .foregroundStyle(TossColor.textTertiary)
            }
        }
    }
}

/// 바텀시트 손잡이.
struct TossSheetHandle: View {
    var body: some View {
        Capsule()
            .fill(TossColor.fill)
            .frame(width: 44, height: 5)
    }
}

/// 얇은 구분선.
struct TossDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(TossColor.separator)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

/// 아이콘 + 제목 + 값으로 구성된 리스트 행.
struct TossInfoRow: View {
    let systemImage: String
    let title: String
    var value: String? = nil
    var tint: Color = TossColor.blue
    var showsChevron = false

    var body: some View {
        HStack(spacing: TossSpacing.m) {
            TossIconBadge(systemName: systemImage, tint: tint, size: 36)

            Text(title)
                .font(TossFont.bodyStrong)
                .foregroundStyle(TossColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let value {
                Text(value)
                    .font(TossFont.body)
                    .foregroundStyle(TossColor.textSecondary)
                    .multilineTextAlignment(.trailing)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TossColor.textTertiary)
            }
        }
        .padding(.horizontal, TossSpacing.l)
        .frame(minHeight: 56)
    }
}

/// 지도 위에 떠 있는 원형 컨트롤.
struct TossFloatingCircleButton: View {
    let systemName: String
    let label: String
    var showsProgress = false
    var size: CGFloat = TossSize.compactControlHeight
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(TossColor.textSecondary)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(TossColor.textPrimary)
                }
            }
            .frame(width: size, height: size)
            .background(TossColor.floatingSurface, in: Circle())
            .overlay { Circle().strokeBorder(TossColor.line, lineWidth: 1) }
            .tossShadow(.floating)
            .contentShape(Circle())
        }
        .buttonStyle(TossScaleButtonStyle())
        .disabled(showsProgress)
        .accessibilityLabel(label)
    }
}

/// 눌렀을 때 살짝 줄어드는 스타일.
struct TossScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(TossMotion.quick, value: configuration.isPressed)
    }
}

/// 비어 있는 상태 안내.
struct TossEmptyState: View {
    let systemImage: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: TossSpacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(TossColor.textTertiary)

            VStack(spacing: TossSpacing.xxs) {
                Text(title)
                    .font(TossFont.title3)
                    .foregroundStyle(TossColor.textPrimary)
                if let message {
                    Text(message)
                        .font(TossFont.caption)
                        .foregroundStyle(TossColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TossSpacing.xxl)
    }
}

// MARK: - Legacy bridge

/// 기존 코드 호환용 별칭. 새 코드는 Toss* 토큰을 직접 사용하세요.
enum FastMapDesign {
    static let accent = TossColor.blue
    static let cardCornerRadius = TossRadius.card
    static let controlHeight = TossSize.controlHeight
    static let compactControlHeight = TossSize.compactControlHeight
    static let horizontalPadding = TossSpacing.l
    static let contentSpacing = TossSpacing.m
}

extension View {
    func fastMapCard(cornerRadius: CGFloat = TossRadius.card) -> some View {
        tossCard(cornerRadius: cornerRadius)
    }
}
