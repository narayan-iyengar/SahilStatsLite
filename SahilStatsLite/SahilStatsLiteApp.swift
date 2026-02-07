//
//  SahilStatsLiteApp.swift
//  SahilStatsLite
//
//  PURPOSE: App entry point, root navigation, and global state management.
//           AppDelegate initializes Firebase and WatchConnectivity at launch.
//           ContentView manages NavigationStack for screen transitions.
//  KEY TYPES: SahilStatsLiteApp, AppDelegate, ContentView, AppState
//  DEPENDS ON: FirebaseService, WatchConnectivityService, GamePersistenceManager
//
//  NOTE: Keep this header updated when modifying this file.
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

        // Start WatchConnectivity session
        _ = WatchConnectivityService.shared
        debugPrint("[AppDelegate] WatchConnectivity service initialized")

        return true
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var appState = AppState()
    @ObservedObject private var watchService = WatchConnectivityService.shared

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

            case .statsEntry:
                ManualGameEntryView()
                    .environmentObject(appState)

            case .summary:
                GameSummaryView()
                    .environmentObject(appState)
            }
        }
        .onChange(of: watchService.pendingGameFromWatch) { _, newGame in
            // Watch triggered a game start - navigate to recording
            if let game = newGame {
                debugPrint("[ContentView] 📱 Starting game from Watch: \(game.teamName) vs \(game.opponent)")
                appState.startGameFromWatch(game)
                // Clear the pending game so it doesn't re-trigger
                watchService.pendingGameFromWatch = nil
            }
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @MainActor @Published var currentScreen: Screen = .home
    @MainActor @Published var currentGame: Game?

    // Log-only mode (no video recording, enter stats after game)
    @MainActor @Published var isLogOnly: Bool = false

    // Stats-only mode (live stats without video recording)
    @MainActor @Published var isStatsOnly: Bool = false

    // Pre-fill data from calendar (cleared after use)
    @MainActor @Published var pendingCalendarGame: (opponent: String, location: String, team: String?)?

    // Recent games now come from persistence
    var recentGames: [Game] {
        GamePersistenceManager.shared.savedGames
    }

    enum Screen {
        case home
        case setup
        case recording
        case statsEntry  // Manual stats entry (no video)
        case summary
    }

    @MainActor
    func startNewGame(opponent: String, teamName: String, location: String?) {
        currentGame = Game(opponent: opponent, teamName: teamName, location: location)
        currentScreen = .recording
    }

    @MainActor
    func startGameFromWatch(_ watchGame: WatchGame) {
        // Create game from Watch data
        var game = Game(
            opponent: watchGame.opponent,
            teamName: watchGame.teamName,
            location: watchGame.location.isEmpty ? nil : watchGame.location
        )
        game.halfLength = watchGame.halfLength

        currentGame = game
        currentScreen = .recording

        debugPrint("[AppState] 📱 Started game from Watch: \(game.teamName) vs \(game.opponent), \(game.halfLength) min halves")
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
