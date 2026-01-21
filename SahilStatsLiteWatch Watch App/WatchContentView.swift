//
//  WatchContentView.swift
//  SahilStatsLiteWatch
//
//  Main content view with TabView for swipe navigation between scoring and stats
//

import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var connectivity: WatchConnectivityClient
    @State private var selectedTab: Int = 0

    var body: some View {
        Group {
            if connectivity.hasActiveGame {
                // Game in progress - show scoring interface
                TabView(selection: $selectedTab) {
                    WatchScoringView()
                        .environmentObject(connectivity)
                        .tag(0)

                    WatchStatsView()
                        .environmentObject(connectivity)
                        .tag(1)
                }
                .tabViewStyle(.verticalPage)
            } else {
                // No active game - waiting screen
                waitingView
            }
        }
    }

    private var waitingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "basketball.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)

                Text("SahilStats")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text("Waiting for game...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                if !connectivity.isPhoneReachable {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 10))
                        Text("Phone not connected")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.red.opacity(0.7))
                    .padding(.top, 8)
                }
            }
        }
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchConnectivityClient.shared)
}
