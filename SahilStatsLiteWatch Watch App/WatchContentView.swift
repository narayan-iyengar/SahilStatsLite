//
//  WatchContentView.swift
//  SahilStatsLiteWatch
//
//  PURPOSE: Root navigation view. Shows waiting screen when no game active,
//           vertical TabView (Scoring + Stats) during a game, and upcoming
//           games list from calendar. Handles quick-start game from Watch.
//  KEY TYPES: WatchContentView, WatchGame
//  DEPENDS ON: WatchConnectivityClient, WatchScoringView, WatchStatsView,
//              WatchGameConfirmationView
//
//  NOTE: Keep this header updated when modifying this file.
//

import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var connectivity: WatchConnectivityClient
    @State private var selectedTab: Int = 0
    @State private var showQuickGameConfirmation = false

    var body: some View {
        Group {
            if connectivity.hasActiveGame {
                // Game in progress - show scoring interface with 3 vertical pages
                // Use Digital Crown to scroll: Scoring -> Shooting -> Details
                TabView(selection: $selectedTab) {
                    WatchScoringView()
                        .environmentObject(connectivity)
                        .tag(0)

                    WatchShootingStatsView()
                        .environmentObject(connectivity)
                        .tag(1)
                    
                    WatchOtherStatsView()
                        .environmentObject(connectivity)
                        .tag(2)
                }
                .tabViewStyle(.verticalPage)
            } else {
                // No active game - show game picker
                gamePickerView
            }
        }
    }

    // MARK: - Game Picker View

    private var gamePickerView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Header
                    HStack {
                        Image(systemName: "basketball.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                        Text("SahilStats")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 8)

                    if !connectivity.isPhoneReachable {
                        // Phone not connected
                        VStack(spacing: 8) {
                            Image(systemName: "iphone.slash")
                                .font(.system(size: 24))
                                .foregroundColor(.red.opacity(0.7))
                            Text("Phone not connected")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .padding(.vertical, 20)
                    } else if connectivity.upcomingGames.isEmpty {
                        // No games synced - show quick start
                        VStack(spacing: 8) {
                            Text("No games scheduled")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))

                            quickGameButton
                        }
                        .padding(.vertical, 12)
                    } else {
                        // Show upcoming games
                        VStack(spacing: 8) {
                            // Today's games
                            let todayGames = connectivity.upcomingGames.filter { $0.isToday }
                            if !todayGames.isEmpty {
                                sectionHeader("Today")
                                ForEach(todayGames) { game in
                                    gameRow(game)
                                }
                            }

                            // Upcoming games (not today)
                            let futureGames = connectivity.upcomingGames.filter { !$0.isToday }
                            if !futureGames.isEmpty {
                                sectionHeader("Upcoming")
                                ForEach(futureGames.prefix(5)) { game in
                                    gameRow(game)
                                }
                            }

                            // Quick game option at bottom
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.vertical, 4)

                            quickGameButton
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .sheet(isPresented: $showQuickGameConfirmation) {
                WatchQuickGameConfirmationView()
                    .environmentObject(connectivity)
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Game Row (NavigationLink to confirmation)

    private func gameRow(_ game: WatchGame) -> some View {
        NavigationLink(destination: WatchGameConfirmationView(game: game).environmentObject(connectivity)) {
            HStack(spacing: 8) {
                // Time
                VStack(alignment: .leading, spacing: 2) {
                    if !game.isToday {
                        Text(game.dayString)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    Text(game.timeString)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(width: 50, alignment: .leading)

                // Opponent
                VStack(alignment: .leading, spacing: 2) {
                    Text("vs \(game.opponent)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(game.teamName)
                        .font(.system(size: 9))
                        .foregroundColor(.orange.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Game Button

    private var quickGameButton: some View {
        Button(action: { showQuickGameConfirmation = true }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                Text("Quick Game")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchConnectivityClient.shared)
}
