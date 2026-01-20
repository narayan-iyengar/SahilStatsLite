//
//  SahilStatsLiteApp.swift
//  SahilStatsLite
//
//  Simplified basketball recording app with auto-tracking and score overlay
//

import SwiftUI
import FirebaseCore
import GoogleSignIn
import Combine

@main
struct SahilStatsLiteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
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
                UltraMinimalRecordingView()
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

    // Pre-fill data from calendar (cleared after use)
    @MainActor @Published var pendingCalendarGame: (opponent: String, location: String)?

    // Recent games now come from persistence
    var recentGames: [Game] {
        GamePersistenceManager.shared.savedGames
    }

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
            game.videoURL = RecordingManager.shared.getRecordingURL()
            // Game is saved by UltraMinimalRecordingView before calling this
            currentScreen = .summary
        }
    }

    @MainActor
    func goHome() {
        currentGame = nil
        currentScreen = .home
    }
}
