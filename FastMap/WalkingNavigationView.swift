import MapKit
import SwiftUI

struct WalkingNavigationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigation: WalkingNavigationController
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var liveActivityController: LiveActivityController

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isShowingSteps = false

    var body: some View {
        ZStack {
            navigationMap

            VStack(spacing: TossSpacing.m) {
                instructionCard
                Spacer(minLength: 0)
                recenterButton
                bottomCard
            }
            .safeAreaPadding(.horizontal, TossEdge.screenInset)
            .safeAreaPadding(.vertical, TossEdge.bottomInset)
        }
        .onAppear {
            focusOnUser()
        }
        .sheet(isPresented: $isShowingSteps) {
            routeStepsSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(TossRadius.sheet)
        }
    }

    private var navigationMap: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            if let destination = navigation.destination {
                Marker(destination.name, systemImage: "flag.checkered", coordinate: destination.coordinate)
                    .tint(TossColor.blue)
            }

            if let route = navigation.route {
                MapPolyline(route.polyline)
                    .stroke(TossColor.blue.opacity(0.22), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                MapPolyline(route.polyline)
                    .stroke(TossColor.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
    }

    // MARK: - Top instruction

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            HStack(spacing: TossSpacing.l) {
                // 다음 동작 아이콘. 다이나믹 아일랜드와 같은 기호를 씁니다.
                Image(systemName: navigation.upcomingManeuvers.first?.symbolName ?? "arrow.up")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(TossColor.textOnBlue)
                    .frame(width: 52, height: 52)
                    .background(TossColor.blue, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(navigation.isRerouting ? "경로 재탐색 중" : GeoMath.formattedDistance(navigation.distanceToManeuver))
                        .font(TossFont.captionStrong)
                        .foregroundStyle(TossColor.blue)

                    Text(navigation.currentInstruction)
                        .font(TossFont.title3)
                        .foregroundStyle(TossColor.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 목적지 방향을 가리키는 나침반. 걸을 때 방향 감을 잡는 용도입니다.
                Image(systemName: "location.north.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TossColor.blue)
                    .frame(width: 34, height: 34)
                    .background(TossColor.blueWeak, in: Circle())
                    .rotationEffect(.degrees(navigation.arrowRotation(
                        deviceHeadingDegrees: locationService.headingDegrees,
                        from: locationService.currentLocation
                    )))
                    .animation(TossMotion.quick, value: locationService.headingDegrees)
                    .accessibilityLabel("목적지 방향")
            }

            // 다이나믹 아일랜드와 같은 순서로 앞으로 올 동작을 미리 보여 줍니다.
            if navigation.upcomingManeuvers.count > 1 {
                maneuverStrip
            }
        }
        .padding(TossSpacing.l)
        .tossConcentricCard()
    }

    private var maneuverStrip: some View {
        HStack(spacing: TossSpacing.s) {
            ForEach(Array(navigation.upcomingManeuvers.enumerated()), id: \.offset) { offset, maneuver in
                Image(systemName: maneuver.symbolName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(offset == 0 ? TossColor.blue : TossColor.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        offset == 0 ? TossColor.blueWeak : TossColor.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .accessibilityLabel(maneuver.title)

                if offset < navigation.upcomingManeuvers.count - 1 {
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TossColor.textTertiary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var recenterButton: some View {
        TossFloatingCircleButton(systemName: "location.fill", label: "현재 위치 따라가기") {
            focusOnUser()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Bottom card

    private var bottomCard: some View {
        VStack(spacing: TossSpacing.l) {
            HStack(alignment: .firstTextBaseline, spacing: TossSpacing.s) {
                Text(WalkingNavigationController.formattedTime(navigation.remainingTravelTime))
                    .font(TossFont.display)
                    .foregroundStyle(TossColor.textPrimary)

                Text("남음")
                    .font(TossFont.callout)
                    .foregroundStyle(TossColor.textSecondary)

                Spacer(minLength: 0)

                Text(GeoMath.formattedDistance(navigation.remainingDistance))
                    .font(TossFont.headline)
                    .foregroundStyle(TossColor.textSecondary)
            }

            if let errorMessage = navigation.errorMessage {
                Text(errorMessage)
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: TossSpacing.s) {
                Button {
                    isShowingSteps = true
                } label: {
                    Label("경로 목록", systemImage: "list.bullet")
                        .lineLimit(1)
                }
                .buttonStyle(TossSecondaryButtonStyle())

                Button {
                    Task { await endNavigation() }
                } label: {
                    Text("길안내 종료")
                        .lineLimit(1)
                }
                .buttonStyle(
                    TossSecondaryButtonStyle(
                        foreground: TossColor.red,
                        background: TossColor.redWeak
                    )
                )
            }
        }
        .padding(TossSpacing.xl)
        .tossConcentricCard()
    }

    // MARK: - Steps sheet

    private var routeStepsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(navigation.steps.enumerated()), id: \.offset) { index, step in
                        routeStepRow(index: index, step: step)

                        if index < navigation.steps.count - 1 {
                            TossDivider(leadingInset: 44)
                        }
                    }
                }
                .padding(.vertical, TossSpacing.xxs)
                .tossCard()
                .padding(.horizontal, TossSpacing.xl)
                .padding(.vertical, TossSpacing.l)
            }
            .scrollIndicators(.hidden)
            .tossPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("전체 경로")
                        .font(TossFont.title3)
                        .foregroundStyle(TossColor.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { isShowingSteps = false }
                        .font(TossFont.headline)
                        .foregroundStyle(TossColor.blue)
                }
            }
            .toolbarBackground(TossColor.background, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
    }

    private func routeStepRow(index: Int, step: MKRoute.Step) -> some View {
        let isComplete = index < navigation.currentStepIndex
        let isCurrent = index == navigation.currentStepIndex

        return HStack(alignment: .top, spacing: TossSpacing.m) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : isCurrent ? "location.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isCurrent ? TossColor.blue : isComplete ? TossColor.green : TossColor.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.instructions.isEmpty ? "경로를 따라 이동" : step.instructions)
                    .font(isCurrent ? TossFont.bodyStrong : TossFont.body)
                    .foregroundStyle(isComplete ? TossColor.textTertiary : TossColor.textPrimary)

                Text(GeoMath.formattedDistance(step.distance))
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TossSpacing.l)
        .padding(.vertical, TossSpacing.m)
    }

    private func focusOnUser() {
        cameraPosition = .userLocation(
            followsHeading: true,
            fallback: .region(
                MKCoordinateRegion(
                    center: locationService.currentLocation,
                    span: .init(latitudeDelta: 0.006, longitudeDelta: 0.006)
                )
            )
        )
    }

    private func endNavigation() async {
        navigation.stop()
        locationService.startEfficientUpdates()
        await liveActivityController.end()
        dismiss()
    }
}
