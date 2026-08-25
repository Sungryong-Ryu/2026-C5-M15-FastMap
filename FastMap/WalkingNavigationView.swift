import MapKit
import SwiftUI
import UIKit

private enum WalkingNavigationSheet: String, Identifiable {
    case routeSteps
    case musicConnection

    var id: String { rawValue }
}

struct WalkingNavigationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigation: WalkingNavigationController
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var liveActivityController: LiveActivityController
    @EnvironmentObject private var store: CafeStore

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isFollowingUser = true
    @State private var presentedSheet: WalkingNavigationSheet?
    @StateObject private var music = NavigationMusicController()

    var body: some View {
        ZStack {
            navigationMap

            VStack(spacing: TossSpacing.s) {
                instructionCard
                Spacer(minLength: 0)
                recenterButton
                bottomCard
            }
            .safeAreaPadding(.horizontal, TossEdge.screenInset)
            .safeAreaPadding(.top, TossSpacing.s)
            .safeAreaPadding(.bottom, TossEdge.bottomInset)
        }
        .onAppear {
            focusOnUser()
            music.startObserving()
        }
        .onDisappear { music.stopObserving() }
        .onChange(of: locationService.currentLocation) { _, _ in
            updateFollowingCamera()
        }
        .onChange(of: locationService.navigationHeadingDegrees) { _, _ in
            updateFollowingCamera()
        }
        .onChange(of: cameraPosition.positionedByUser) { _, positionedByUser in
            if positionedByUser { isFollowingUser = false }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .routeSteps:
                routeStepsSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(TossRadius.sheet)
            case .musicConnection:
                MusicConnectionSheet(music: music)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(TossRadius.sheet)
            }
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
        HStack(spacing: TossSpacing.m) {
            Image(systemName: currentStepSymbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TossColor.textOnBlue)
                .frame(width: 40, height: 40)
                .background(MusicGradient.accent, in: Circle())
                .shadow(color: TossColor.blue.opacity(0.30), radius: 12, y: 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: TossSpacing.s) {
                    Label(
                        WalkingNavigationController.formattedTime(navigation.remainingTravelTime),
                        systemImage: "clock.fill"
                    )
                        .font(TossFont.captionStrong)
                        .foregroundStyle(TossColor.blue)
                        .monospacedDigit()

                    Capsule()
                        .fill(TossColor.separator)
                        .frame(width: 1, height: 11)

                    Label(
                        GeoMath.formattedDistance(navigation.remainingDistance),
                        systemImage: "location.fill"
                    )
                    .font(TossFont.captionStrong)
                    .foregroundStyle(TossColor.textSecondary)
                    .monospacedDigit()

                    Spacer(minLength: 2)
                    compactManeuverStrip
                }

                Text(
                    navigation.isRerouting
                        ? navigation.currentInstruction
                        : "\(GeoMath.formattedDistance(navigation.distanceToManeuver)) 후 · \(navigation.currentInstruction)"
                )
                    .font(TossFont.bodyStrong)
                    .foregroundStyle(TossColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "location.north.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TossColor.blue)
                .frame(width: 30, height: 30)
                .background(TossColor.blueWeak, in: Circle())
                .rotationEffect(.degrees(navigation.arrowRotation(
                    deviceHeadingDegrees: locationService.navigationHeadingDegrees,
                    from: locationService.currentLocation
                )))
                .animation(TossMotion.quick, value: locationService.navigationHeadingDegrees)
                .accessibilityLabel("목적지 방향")
        }
        .padding(TossSpacing.m)
        .tossConcentricCard()
    }

    private var compactManeuverStrip: some View {
        HStack(spacing: TossSpacing.xs) {
            ForEach(Array(navigation.upcomingManeuvers.dropFirst().prefix(3).enumerated()), id: \.offset) { _, maneuver in
                Image(systemName: maneuver.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TossColor.textTertiary)
                    .accessibilityLabel(maneuver.title)
            }
        }
    }

    private var recenterButton: some View {
        TossFloatingCircleButton(
            systemName: isFollowingUser ? "location.fill" : "location.north.fill",
            label: "현재 위치와 방향 따라가기",
            size: 38,
            tint: isFollowingUser ? nil : TossColor.blue
        ) {
            focusOnUser()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Bottom card

    private var bottomCard: some View {
        VStack(spacing: TossSpacing.s) {
            navigationModePicker

            HStack(spacing: TossSpacing.s) {
                if let route = navigation.route {
                    Label(route.provider.title, systemImage: navigation.mode.systemImage)
                        .font(TossFont.captionStrong)
                        .foregroundStyle(TossColor.textSecondary)
                        .padding(.horizontal, TossSpacing.s)
                        .frame(height: 28)
                        .background(MusicGradient.softAccent, in: Capsule())
                }

                Spacer(minLength: TossSpacing.xs)

                compactActionButton(
                    systemName: "list.bullet",
                    label: "경로 목록",
                    foreground: TossColor.textPrimary,
                    background: TossColor.surfaceAlt
                ) {
                    presentedSheet = .routeSteps
                }

                compactActionButton(
                    systemName: "xmark",
                    label: "길안내 종료",
                    foreground: TossColor.red,
                    background: TossColor.redWeak
                ) {
                    Task { await endNavigation() }
                }
            }

            musicBar

            if let detailText = navigation.route?.detailText {
                Text(detailText)
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage = navigation.errorMessage {
                Text(errorMessage)
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .padding(TossSpacing.m)
        .tossConcentricCard()
    }

    private var navigationModePicker: some View {
        HStack(spacing: TossSpacing.xs) {
            ForEach(NavigationMode.allCases) { mode in
                Button {
                    Task { await changeMode(to: mode) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.title)
                            .font(TossFont.captionStrong)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(navigation.mode == mode ? TossColor.blue : TossColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(
                        navigation.mode == mode
                            ? AnyShapeStyle(MusicGradient.softAccent)
                            : AnyShapeStyle(TossColor.surfaceAlt),
                        in: Capsule()
                    )
                }
                .buttonStyle(TossScaleButtonStyle())
                .disabled(navigation.isRerouting || navigation.mode == mode)
                .accessibilityLabel("\(mode.title) 경로로 변경")
                .accessibilityAddTraits(navigation.mode == mode ? .isSelected : [])
            }
        }
    }

    private var musicBar: some View {
        HStack(spacing: TossSpacing.s) {
            Group {
                if let artwork = music.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: music.isOtherAudioPlaying ? "waveform" : "music.note")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TossColor.blue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(TossColor.blueWeak)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: TossRadius.icon, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(music.title)
                    .font(TossFont.bodyStrong)
                    .foregroundStyle(TossColor.textPrimary)
                    .lineLimit(1)
                Text(music.artist)
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if music.canControlMusic {
                HStack(spacing: TossSpacing.s) {
                    Button(action: music.skipToPrevious) {
                        Image(systemName: "backward.fill")
                    }
                    Button(action: music.togglePlayback) {
                        Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Button(action: music.skipToNext) {
                        Image(systemName: "forward.fill")
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TossColor.textPrimary)
                .buttonStyle(.plain)
            } else {
                Button("연결") { presentedSheet = .musicConnection }
                    .font(TossFont.buttonSmall)
                    .foregroundStyle(TossColor.blue)
                    .buttonStyle(.plain)
            }
        }
        .padding(TossSpacing.xs)
        .background {
            RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                        .fill(TossColor.surfaceAlt.opacity(0.72))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                        .fill(MusicGradient.softAccent)
                }
        }
        .accessibilityElement(children: .contain)
    }

    private func compactActionButton(
        systemName: String,
        label: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 34, height: 34)
                .background(background, in: Circle())
        }
        .buttonStyle(TossScaleButtonStyle())
        .accessibilityLabel(label)
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
                    Button("완료") { presentedSheet = nil }
                        .font(TossFont.headline)
                        .foregroundStyle(TossColor.blue)
                }
            }
            .toolbarBackground(TossColor.background.opacity(0.88), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
    }

    private func routeStepRow(index: Int, step: NavigationRouteStep) -> some View {
        let isComplete = index < navigation.currentStepIndex
        let isCurrent = index == navigation.currentStepIndex

        return HStack(alignment: .top, spacing: TossSpacing.m) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : isCurrent ? "location.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isCurrent ? TossColor.blue : isComplete ? TossColor.green : TossColor.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.instruction.isEmpty ? "경로를 따라 이동" : step.instruction)
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
        isFollowingUser = true
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: locationService.currentLocation,
                distance: navigationCameraDistance,
                heading: locationService.navigationHeadingDegrees,
                pitch: 48
            )
        )
    }

    private func updateFollowingCamera() {
        guard isFollowingUser else { return }
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: locationService.currentLocation,
                distance: navigationCameraDistance,
                heading: locationService.navigationHeadingDegrees,
                pitch: 48
            )
        )
    }

    private var navigationCameraDistance: CLLocationDistance {
        switch navigation.mode {
        case .walking: 480
        case .bicycle: 650
        case .automobile: 900
        case .transit: 780
        }
    }

    private var currentStepSymbol: String {
        if navigation.mode == .transit,
           navigation.steps.indices.contains(navigation.currentStepIndex),
           let symbol = navigation.steps[navigation.currentStepIndex].systemImage {
            return symbol
        }
        return navigation.upcomingManeuvers.first?.symbolName ?? navigation.mode.systemImage
    }

    private func changeMode(to mode: NavigationMode) async {
        await navigation.changeMode(to: mode, from: locationService.currentLocation)
        locationService.startNavigationUpdates(for: navigation.mode)
        focusOnUser()

        guard let cafe = navigation.destination, var snapshot = navigation.snapshot else { return }
        snapshot = snapshot.withArrowRotation(
            navigation.arrowRotation(
                deviceHeadingDegrees: locationService.headingDegrees,
                from: locationService.currentLocation
            )
        )
        await liveActivityController.updateNavigation(cafe: cafe, snapshot: snapshot)
    }

    private func endNavigation() async {
        navigation.stop()
        // 촘촘한 거리 필터(50~500m)를 켜 뒀을 때만 정밀 갱신으로 돌아갑니다.
        if store.needsPreciseLocation {
            locationService.startProximityUpdates()
        } else {
            locationService.startEfficientUpdates()
        }
        await liveActivityController.end()
        dismiss()
    }
}
