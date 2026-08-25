//
//  LaunchSplashView.swift
//  WhereismyAHAH
//
//  앱이 시작될 때 브랜드 색상과 머그 로고만 잠시 보여 줍니다.
//

import SwiftUI

struct LaunchSplashView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TossColor.appIconBackground

                Image(systemName: "mug.fill")
                    .font(.system(
                        size: min(proxy.size.width * 0.15, 112),
                        weight: .regular
                    ))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(TossColor.appIconInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct LaunchSplashView_Previews: PreviewProvider {
    static var previews: some View {
        LaunchSplashView()
            .preferredColorScheme(.dark)
    }
}
