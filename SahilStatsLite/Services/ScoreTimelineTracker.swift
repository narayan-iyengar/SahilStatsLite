//
//  ScoreTimelineTracker.swift
//  SahilStatsLite
//
//  Tracks score changes with timestamps for post-processing video overlays
//

import Foundation
import Combine

class ScoreTimelineTracker: ObservableObject {
    static let shared = ScoreTimelineTracker()

    struct ScoreSnapshot: Codable {
        let timestamp: TimeInterval  // Seconds from start of recording
        let homeScore: Int
        let awayScore: Int
        let quarter: Int
        let clockTime: String
        let homeTeam: String
        let awayTeam: String
    }

    private var recordingStartTime: Date?
    private(set) var snapshots: [ScoreSnapshot] = []
    private var lastSnapshot: ScoreSnapshot?
    private var captureTimer: Timer?

    // Current game state
    private var homeTeam: String = ""
    private var awayTeam: String = ""
    private var homeScore: Int = 0
    private var awayScore: Int = 0
    private var quarter: Int = 1
    private var clockTime: String = "0:00"

    @Published private(set) var isRecording: Bool = false

    private init() {}

    // MARK: - Recording Control

    /// Start timeline recording
    func startRecording(homeTeam: String, awayTeam: String, quarterLength: Int) {
        stopRecording()

        recordingStartTime = Date()
        snapshots = []
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.homeScore = 0
        self.awayScore = 0
        self.quarter = 1
        self.clockTime = "\(quarterLength):00"
        isRecording = true

        // Capture initial state
        let initialSnapshot = ScoreSnapshot(
            timestamp: 0,
            homeScore: 0,
            awayScore: 0,
            quarter: 1,
            clockTime: clockTime,
            homeTeam: homeTeam,
            awayTeam: awayTeam
        )

        snapshots.append(initialSnapshot)
        lastSnapshot = initialSnapshot

        // Capture state every second for smooth clock updates
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.captureCurrentState()
        }

        debugPrint("📊 ScoreTimelineTracker: Recording started")
    }

    /// Update score (call this when +1/+2/+3 is pressed)
    func updateScore(homeScore: Int, awayScore: Int) {
        self.homeScore = homeScore
        self.awayScore = awayScore

        // Immediately capture score changes
        captureCurrentState()
        debugPrint("📊 Score updated: \(homeScore) - \(awayScore)")
    }

    /// Update clock display (call this every second from RecordingView)
    func updateClock(clockTime: String, quarter: Int) {
        self.clockTime = clockTime
        self.quarter = quarter
    }

    /// Capture the current state
    private func captureCurrentState() {
        guard let startTime = recordingStartTime else { return }

        let timestamp = Date().timeIntervalSince(startTime)

        let snapshot = ScoreSnapshot(
            timestamp: timestamp,
            homeScore: homeScore,
            awayScore: awayScore,
            quarter: quarter,
            clockTime: clockTime,
            homeTeam: homeTeam,
            awayTeam: awayTeam
        )

        snapshots.append(snapshot)
        lastSnapshot = snapshot
    }

    /// Stop recording and return the timeline
    @discardableResult
    func stopRecording() -> [ScoreSnapshot] {
        captureTimer?.invalidate()
        captureTimer = nil

        let timeline = snapshots

        debugPrint("📊 ScoreTimelineTracker: Stopped")
        debugPrint("   Total snapshots: \(timeline.count)")

        if let first = timeline.first, let last = timeline.last {
            let duration = last.timestamp - first.timestamp
            debugPrint("   Duration: \(String(format: "%.1f", duration))s")
        }

        // Reset state
        recordingStartTime = nil
        snapshots = []
        lastSnapshot = nil
        isRecording = false

        return timeline
    }

    // MARK: - Timeline Access

    func getSnapshotAt(time: TimeInterval) -> ScoreSnapshot? {
        guard !snapshots.isEmpty else { return nil }

        var result = snapshots[0]
        for snapshot in snapshots {
            if snapshot.timestamp <= time {
                result = snapshot
            } else {
                break
            }
        }

        return result
    }
}
