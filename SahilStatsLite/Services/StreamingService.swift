//
//  StreamingService.swift
//  SahilStatsLite
//
//  Thin @MainActor wrapper around SahilRTMPStreamer.
//  No HaishinKit dependency — the underlying streamer handles all RTMP + FLV + codec work.
//

import Foundation
import AVFoundation
import Combine

// MARK: - Stream Health

enum StreamHealth: Equatable {
    case idle
    case connecting
    case live
    case reconnecting
    case failed(String)

    var label: String {
        switch self {
        case .idle:          return "Not streaming"
        case .connecting:    return "Connecting…"
        case .live:          return "LIVE"
        case .reconnecting:  return "Reconnecting…"
        case .failed(let e): return "Failed: \(e)"
        }
    }

    var isActive: Bool {
        switch self { case .live, .reconnecting: return true; default: return false }
    }
}

// MARK: - Streaming Service

@MainActor
final class StreamingService: ObservableObject {
    static let shared = StreamingService()

    @Published var isStreaming: Bool = false
    @Published var health: StreamHealth = .idle

    static let streamKeyDefaultsKey        = "SahilStats_YouTubeStreamKey"
    static let streamingEnabledDefaultsKey = "SahilStats_StreamingEnabled"
    static let liveURLDefaultsKey          = "SahilStats_YouTubeLiveURL"

    var savedStreamKey: String {
        get { UserDefaults.standard.string(forKey: Self.streamKeyDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.streamKeyDefaultsKey) }
    }

    var streamingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.streamingEnabledDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.streamingEnabledDefaultsKey) }
    }

    /// The YouTube watch URL shared with parents (e.g. youtube.com/@niyengar/live)
    var liveStreamURL: String {
        get { UserDefaults.standard.string(forKey: Self.liveURLDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.liveURLDefaultsKey) }
    }

    private let rtmp = SahilRTMPStreamer()
    private init() {
        rtmp.onLive = { [weak self] in
            self?.health = .live
            self?.debugLog("🔴 LIVE → YouTube")
        }
        rtmp.onFailed = { [weak self] msg in
            self?.health = .failed(msg)
            self?.isStreaming = false
            self?.debugLog("❌ \(msg)")
        }
    }

    // MARK: - Lifecycle

    func startStream() async {
        guard !savedStreamKey.isEmpty else {
            health = .failed("No stream key — add one in Settings")
            return
        }
        health = .connecting
        isStreaming = true
        debugLog("Starting stream with key \(savedStreamKey.prefix(8))...")
        rtmp.start(streamKey: savedStreamKey)
    }

    func stopStream() async {
        rtmp.stop()
        isStreaming = false
        health = .idle
    }

    // MARK: - Frame Injection

    nonisolated func appendVideoBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        rtmp.appendVideo(pixelBuffer, timestamp: timestamp)
    }

    nonisolated func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        rtmp.appendAudio(sampleBuffer)
    }

    private func debugLog(_ msg: String) {
        debugPrint("[Stream] \(msg)")
    }
}
