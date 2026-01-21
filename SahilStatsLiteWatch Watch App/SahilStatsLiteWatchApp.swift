//
//  SahilStatsLiteWatchApp.swift
//  SahilStatsLiteWatch Watch App
//
//  Apple Watch companion app for basketball game scoring
//

import SwiftUI

@main
struct SahilStatsLiteWatchApp: App {
    @StateObject private var connectivityService = WatchConnectivityClient.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(connectivityService)
        }
    }
}
