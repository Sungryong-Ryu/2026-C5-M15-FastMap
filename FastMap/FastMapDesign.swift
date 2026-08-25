//
//  FastMapDesign.swift
//  WhereismyAHAH
//
//  상단 오로라와 깊은 블랙 대비를 중심으로 한 다크 디자인 시스템.
//  기존 Toss* 이름은 화면 구조를 안전하게 유지하기 위한 호환 이름입니다.
//  - 화면 상단에만 집중된 블루 / 선셋 광원
//  - 그라데이션을 걷어낸 단단한 카드와 선명한 CTA
//  - 큰 제목, 충분한 여백, 높은 텍스트 대비
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

enum TossPalette {
    static let base: UInt32 = 0x050607
    static let surface1: UInt32 = 0x121416
    static let surface2: UInt32 = 0x1A1D20
    static let surface3: UInt32 = 0x24282C
    static let line: UInt32 = 0x353A40

    static let textPrimary: UInt32 = 0xF8FAFC
    static let textSecondary: UInt32 = 0xC8CDD5
    static let textTertiary: UInt32 = 0xA0A7B2

    static let blue: UInt32 = 0x3478F6
    static let bluePressed: UInt32 = 0x245ED6
    static let blueWeak: UInt32 = 0x10254A

    static let red: UInt32 = 0xFF453A
    static let redWeak: UInt32 = 0x351817
    static let green: UInt32 = 0x30D98B
    static let yellow: UInt32 = 0xFFD45A
}

/// 앱 전역에서 사용하는 시맨틱 컬러.
enum TossColor {
    /// 홈 화면 앱 아이콘과 시작 화면이 공유하는 브랜드 배경색.
    static let appIconBackground = tossColor(0x68C7FE)
    /// 시작 화면 머그 로고. 기존 앱 아이콘의 커피잔 색과 같습니다.
    static let appIconInk = tossColor(0x101E26)
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
    static let floatingSurface = tossColor(0x111417)
}

/// 그라데이션은 배경 광원과 주요 CTA에만 제한적으로 사용합니다.
enum MusicGradient {
    static let accent = LinearGradient(
        colors: [tossColor(0x285EFF), tossColor(0x357DFF), tossColor(0x58C7FF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmAccent = LinearGradient(
        colors: [tossColor(0xFF3934), tossColor(0xFF613E), tossColor(0xFFB24E)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let softAccent = LinearGradient(
        colors: [tossColor(0x3478F6).opacity(0.28), tossColor(0x58C7FF).opacity(0.08), .clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let softWarm = LinearGradient(
        colors: [tossColor(0xFF4A38).opacity(0.25), tossColor(0xFFB24E).opacity(0.07), .clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// 레퍼런스처럼 광원을 상단에 모으고, 콘텐츠 영역은 블랙으로 가라앉힙니다.
struct MusicBackdrop: View {
    enum Tone {
        case cool
        case sunset
    }

    var tone: Tone = .cool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationOrigin = Date()
    @State private var motionSeed = Double.random(in: 0 ..< (.pi * 2))

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let elapsed = reduceMotion ? 0 : timeline.date.timeIntervalSince(animationOrigin)
            animatedBackdrop(at: elapsed)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func animatedBackdrop(at elapsed: TimeInterval) -> some View {
        // 서로 다른 느린 파동을 섞어 반복 패턴이 쉽게 읽히지 않게 합니다.
        // 화면이 열릴 때 정해지는 motionSeed 덕분에 매번 다른 위치에서 출발합니다.
        let fieldX = organicWave(elapsed, speed: 0.50, phase: motionSeed)
        let fieldY = organicWave(elapsed, speed: 0.42, phase: motionSeed + 1.7)
        let fieldTurn = organicWave(elapsed, speed: 0.30, phase: motionSeed + 3.2)
        let highlightX = organicWave(elapsed, speed: 0.72, phase: motionSeed + 0.8)
        let highlightY = organicWave(elapsed, speed: 0.58, phase: motionSeed + 2.6)
        let secondaryX = organicWave(elapsed, speed: 0.65, phase: motionSeed + 4.1)
        let secondaryY = organicWave(elapsed, speed: 0.46, phase: motionSeed + 5.4)
        let breathing = organicWave(elapsed, speed: 0.52, phase: motionSeed + 1.1)

        return ZStack {
            TossColor.background

            LinearGradient(
                gradient: Gradient(stops: fieldStops),
                startPoint: UnitPoint(
                    x: 0.88 + CGFloat(fieldX * 0.15),
                    y: -0.04 + CGFloat(fieldY * 0.10)
                ),
                endPoint: UnitPoint(
                    x: 0.48 - CGFloat(fieldX * 0.11),
                    y: 1.02
                )
            )
            .scaleEffect(1.14 + CGFloat(breathing * 0.045))
            .rotationEffect(.degrees(fieldTurn * 4.0))
            .blur(radius: 18)

            RadialGradient(
                colors: [
                    highlightColor.opacity(0.90 + breathing * 0.09),
                    highlightColor.opacity(0.22),
                    .clear
                ],
                center: UnitPoint(
                    x: 0.78 + CGFloat(highlightX * 0.17),
                    y: -0.02 + CGFloat(highlightY * 0.13)
                ),
                startRadius: 0,
                endRadius: 360 + CGFloat(breathing * 44)
            )
            .blur(radius: 22)

            RadialGradient(
                colors: [
                    secondaryGlow.opacity(0.58 - breathing * 0.10),
                    secondaryGlow.opacity(0.12),
                    .clear
                ],
                center: UnitPoint(
                    x: 0.10 + CGFloat(secondaryX * 0.19),
                    y: 0.22 + CGFloat(secondaryY * 0.15)
                ),
                startRadius: 0,
                endRadius: 420 - CGFloat(breathing * 46)
            )
            .blur(radius: 26)

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.34), location: 0.00),
                    .init(color: Color.black.opacity(0.18), location: 0.30),
                    .init(color: TossColor.background.opacity(0.12), location: 0.44),
                    .init(color: TossColor.background.opacity(0.82), location: 0.63),
                    .init(color: TossColor.background, location: 0.82)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// 두 주파수와 무작위 위상을 합친 -1...1 범위의 유기적인 이동값.
    private func organicWave(_ time: TimeInterval, speed: Double, phase: Double) -> Double {
        let primary = sin((time * speed) + phase)
        let secondary = sin((time * speed * 0.37) + (phase * 1.83))
        return (primary * 0.72) + (secondary * 0.28)
    }

    private var fieldStops: [Gradient.Stop] {
        switch tone {
        case .cool:
            [
                .init(color: tossColor(0xC5E3FF), location: 0.00),
                .init(color: tossColor(0x3977FF), location: 0.14),
                .init(color: tossColor(0x173D9D), location: 0.32),
                .init(color: tossColor(0x09142E), location: 0.52),
                .init(color: TossColor.background, location: 0.76)
            ]
        case .sunset:
            [
                .init(color: tossColor(0xFFD07C), location: 0.00),
                .init(color: tossColor(0xFF793F), location: 0.15),
                .init(color: tossColor(0xF13F31), location: 0.32),
                .init(color: tossColor(0x581820), location: 0.53),
                .init(color: TossColor.background, location: 0.76)
            ]
        }
    }

    private var highlightColor: Color {
        switch tone {
        case .cool: tossColor(0xD8ECFF)
        case .sunset: tossColor(0xFFE1A4)
        }
    }

    private var secondaryGlow: Color {
        switch tone {
        case .cool: tossColor(0x11BBD4)
        case .sunset: tossColor(0xFF342D)
        }
    }
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
        Option(id: "blue", title: "일렉트릭 블루", color: TossColor.blue),
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

/// Apple Music처럼 화면 제목은 크고 무겁게, 정보는 대비를 낮춰 계층을 만듭니다.
enum TossFont {
    /// 화면 대표 타이틀
    static let display = Font.system(size: 32, weight: .heavy)
    static let title1 = Font.system(size: 27, weight: .bold)
    static let title2 = Font.system(size: 21, weight: .bold)
    static let title3 = Font.system(size: 18, weight: .bold)

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
    static let field: CGFloat = 14
    static let button: CGFloat = 16
    static let card: CGFloat = 22
    static let sheet: CGFloat = 30
    static let icon: CGFloat = 12
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
    /// 지도 위에 얹는 칩. 지도를 덜 가리도록 한 단계 낮춥니다.
    static let compactChipHeight: CGFloat = 34
    static let fieldHeight: CGFloat = 50
    static let iconBadge: CGFloat = 40
}

enum TossMotion {
    static let snappy = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let quick = Animation.spring(response: 0.22, dampingFraction: 0.9)
}

// MARK: - Elevation

/// 어두운 서피스 사이에도 깊이가 느껴지도록 넓고 옅은 그림자를 사용합니다.
enum TossShadow {
    case none
    /// 앨범·플레이리스트 카드 같은 부드러운 부양감
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
        case .none:
            content
        case .card:
            content
                .shadow(color: .black.opacity(0.26), radius: 18, y: 8)
        case .floating:
            content
                .shadow(color: .black.opacity(0.38), radius: 16, y: 6)
        case .sheet:
            content
                .shadow(color: .black.opacity(0.46), radius: 30, y: -8)
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
            .background {
                shape
                    .fill(fill.opacity(0.96))
            }
            .overlay {
                if bordered {
                    shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
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
                    .fill(TossColor.surface.opacity(0.97))
                    .overlay { shape.stroke(Color.white.opacity(0.12), lineWidth: 0.8) }
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
    func tossPageBackground(tone: MusicBackdrop.Tone = .cool) -> some View {
        background(MusicBackdrop(tone: tone).ignoresSafeArea())
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
                    .fill(fill.opacity(0.97))
                    .overlay { shape.stroke(Color.white.opacity(0.12), lineWidth: 0.8) }
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

enum TossAccentTheme {
    case cool
    case warm

    var gradient: LinearGradient {
        switch self {
        case .cool: MusicGradient.accent
        case .warm: MusicGradient.warmAccent
        }
    }

    var glow: Color {
        switch self {
        case .cool: TossColor.blue
        case .warm: TossColor.red
        }
    }
}

/// 선명한 색을 CTA 한 곳에 집중합니다.
struct TossPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = TossSize.ctaHeight
    var cornerRadius: CGFloat = TossRadius.button
    var accent: TossAccentTheme = .cool

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, height: height, cornerRadius: cornerRadius, accent: accent)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        let cornerRadius: CGFloat
        let accent: TossAccentTheme

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(TossFont.button)
                .foregroundStyle(isEnabled ? TossColor.textOnBlue : TossColor.textTertiary)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(
                    isEnabled
                        ? AnyShapeStyle(accent.gradient)
                        : AnyShapeStyle(TossColor.fill),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .shadow(color: isEnabled ? accent.glow.opacity(0.24) : .clear, radius: 14, y: 6)
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
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                    }
            }
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
            .background(
                MusicGradient.softAccent,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
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
            .background {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(style == .filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.15)))
            }
            .shadow(color: tint.opacity(style == .filled ? 0.24 : 0.10), radius: 10, y: 5)
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
            .background(
                isSelected ? AnyShapeStyle(MusicGradient.accent) : AnyShapeStyle(TossColor.surfaceAlt),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 지도 위에 얹는 작은 캡슐 칩.
///
/// `TossChip`보다 한 단계 낮고 좁습니다. 지도 화면에서는 필터가 차지하는 세로 공간이
/// 그대로 가려지는 지도 면적이라, 한 줄로 끝나는 크기를 따로 둡니다.
struct TossCompactChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? TossColor.textOnBlue : TossColor.textSecondary)
            .padding(.horizontal, 13)
            .frame(height: TossSize.compactChipHeight)
            .background {
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(MusicGradient.accent) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay {
                        if !isSelected { Capsule().fill(TossColor.floatingSurface.opacity(0.78)) }
                    }
                    .overlay {
                        Capsule().strokeBorder(isSelected ? .clear : TossColor.line, lineWidth: 1)
                    }
                    .tossShadow(.floating)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(TossScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TossTextContrastModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.92), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.54), radius: 6, y: 2)
    }
}

extension View {
    /// 사진·지도·오로라처럼 밝기가 변하는 배경 위 텍스트의 외곽 대비를 확보합니다.
    func tossTextContrast() -> some View {
        modifier(TossTextContrastModifier())
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
                .tossTextContrast()
            Spacer(minLength: TossSpacing.s)
            if let trailing {
                Text(trailing)
                    .font(TossFont.captionStrong)
                    .foregroundStyle(TossColor.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(TossColor.surfaceAlt, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(TossColor.line, lineWidth: 1)
                    }
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
    /// 지금 눌러야 할 버튼이라는 걸 알릴 때 채웁니다. nil이면 평소의 뉴트럴 서피스입니다.
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(tint == nil ? TossColor.textSecondary : TossColor.textOnBlue)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(tint == nil ? TossColor.textPrimary : TossColor.textOnBlue)
                }
            }
            .frame(width: size, height: size)
            .background(
                tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.ultraThinMaterial),
                in: Circle()
            )
            .background(tint == nil ? TossColor.floatingSurface.opacity(0.72) : .clear, in: Circle())
            .overlay { Circle().strokeBorder(tint == nil ? TossColor.line : .clear, lineWidth: 1) }
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
