//
//  SahilStatsLiteWatchApp.swift
//  SahilStatsLiteWatch Watch App
//
//  PURPOSE: Watch app entry point. Initializes WatchConnectivityClient
//           as environment object and presents WatchContentView.
//  KEY TYPES: SahilStatsLiteWatchApp
//  DEPENDS ON: WatchConnectivityClient, WatchContentView
//
//  NOTE: Keep this header updated when modifying this file.
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
