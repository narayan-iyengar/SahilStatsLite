//
//  SahilStatsLiteApp.swift
//  SahilStatsLite
//
//  Simplified basketball recording app with auto-tracking and score overlay
//

import SwiftUI
import FirebaseCore
import Combine

@main
struct SahilStatsLiteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        NavigationStack {
            switch appState.currentScreen {
            case .home:
                HomeView()
                    .environmentObject(appState)

            case .setup:
                GameSetupView()
                    .environmentObject(appState)

            case .recording:
                RecordingView()
                    .environmentObject(appState)

            case .summary:
                GameSummaryView()
                    .environmentObject(appState)
            }
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @MainActor @Published var currentScreen: Screen = .home
    @MainActor @Published var currentGame: Game?
    @MainActor @Published var recentGames: [Game] = []

    enum Screen {
        case home
        case setup
        case recording
        case summary
    }

    @MainActor
    func startNewGame(opponent: String, teamName: String, location: String?) {
        currentGame = Game(opponent: opponent, teamName: teamName, location: location)
        currentScreen = .recording
    }

    @MainActor
    func endGame() {
        if var game = currentGame {
            game.completedAt = Date()
            recentGames.insert(game, at: 0)
            currentScreen = .summary
        }
    }

    @MainActor
    func goHome() {
        currentGame = nil
        currentScreen = .home
    }
}
