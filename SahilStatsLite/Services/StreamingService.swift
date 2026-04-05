//
//  StreamingService.swift
//  SahilStatsLite
//
//  PURPOSE: Live YouTube streaming via RTMP. Receives composited CVPixelBuffer
//           frames from RecordingManager (same frames with scoreboard overlay
//           already burned in) and pushes them to YouTube via HaishinKit.
//           Runs alongside AVAssetWriter — local HEVC recording continues
//           unchanged while stream encodes H.264 in a separate Neural Engine pass.
//
//  SETUP:
//    1. Add HaishinKit via Xcode → File → Add Package Dependencies
//       URL: https://github.com/shogo4405/HaishinKit.swift
//    2. Enter stream key in Settings (YouTube Studio → Go Live → Stream → Stream key)
//    3. Stream key persists in UserDefaults — set once per season
//
//  YOUTUBE REQUIREMENTS:
//    Endpoint: rtmps://a.rtmp.youtube.com/live2
//    Codec:    H.264 (HEVC not accepted on RTMP ingest)
//    Keyframe: every 2 seconds
//    Bitrate:  6 Mbps for 1080p30
//    Latency:  Low latency mode (set in YouTube Studio)
//
//  DEPENDS ON: HaishinKit (SPM), AVFoundation
//

import Foundation
import AVFoundation
import Combine

// HaishinKit import — guarded so the app compiles without the package.
// Remove the #if once HaishinKit is added via SPM.
#if canImport(HaishinKit)
import HaishinKit
#endif

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

    // UserDefaults key — stream key persists across sessions
    static let streamKeyDefaultsKey = "SahilStats_YouTubeStreamKey"

    var savedStreamKey: String {
        get { UserDefaults.standard.string(forKey: Self.streamKeyDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.streamKeyDefaultsKey) }
    }

    private let rtmpURL = "rtmps://a.rtmp.youtube.com/live2"

    #if canImport(HaishinKit)
    private var connection: RTMPConnection?
    private var stream: RTMPStream?
    #endif

    private var videoSize: CGSize = CGSize(width: 1920, height: 1080)

    private init() {}

    // MARK: - Lifecycle

    func startStream() async {
        guard !savedStreamKey.isEmpty else {
            health = .failed("No stream key — add one in Settings")
            return
        }
        #if canImport(HaishinKit)
        await _startStream(key: savedStreamKey)
        #else
        health = .failed("HaishinKit not installed — add via SPM")
        #endif
    }

    func stopStream() async {
        #if canImport(HaishinKit)
        await _stopStream()
        #endif
        isStreaming = false
        health = .idle
    }

    // MARK: - Frame Injection (called from RecordingManager.processVideoFrame)
    // Receives composited CVPixelBuffer — overlay already burned in.
    // This runs on RecordingManager's background processingQueue.

    nonisolated func appendVideoBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        #if canImport(HaishinKit)
        guard let stream else { return }
        // Wrap in CMSampleBuffer for HaishinKit injection
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let fmt = formatDescription else { return }
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmt,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        if let sb = sampleBuffer {
            stream.append(sb, track: 0) // track 0 = video
        }
        #endif
    }

    nonisolated func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        #if canImport(HaishinKit)
        stream?.append(sampleBuffer, track: 1) // track 1 = audio
        #endif
    }

    // MARK: - Private HaishinKit Implementation

    #if canImport(HaishinKit)
    private func _startStream(key: String) async {
        health = .connecting
        isStreaming = true

        let conn = RTMPConnection()
        let strm = RTMPStream(connection: conn)

        // H.264 required — YouTube RTMP ingest does not accept HEVC
        strm.videoSettings = VideoCodecSettings(
            videoSize: videoSize,
            bitRate: 6_000_000,                                    // 6 Mbps for 1080p30
            profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
            maxKeyFrameIntervalDuration: 2                         // keyframe every 2s (YouTube requirement)
        )
        strm.audioSettings = AudioCodecSettings(
            bitRate: 128_000                                       // 128 kbps AAC
        )

        // Observe connection state for health updates
        conn.addEventListener(.rtmpStatus, selector: #selector(handleRTMPStatus(_:)), observer: self)

        self.connection = conn
        self.stream = strm

        do {
            try await conn.connect(rtmpURL)
            try await strm.publish(key)
            health = .live
            debugPrint("[Stream] 🔴 LIVE → YouTube")
        } catch {
            health = .failed(error.localizedDescription)
            isStreaming = false
            debugPrint("[Stream] ❌ Failed: \(error.localizedDescription)")
        }
    }

    private func _stopStream() async {
        do {
            try await stream?.close()
            try await connection?.close()
        } catch {
            debugPrint("[Stream] Stop error: \(error.localizedDescription)")
        }
        connection = nil
        stream = nil
    }

    @objc private func handleRTMPStatus(_ notification: Notification) {
        guard let info = notification.userInfo,
              let code = info["code"] as? String else { return }

        Task { @MainActor in
            switch code {
            case "NetStream.Publish.Start":
                self.health = .live
            case "NetConnection.Connect.Closed", "NetStream.Publish.BadName":
                if self.isStreaming {
                    self.health = .reconnecting
                    debugPrint("[Stream] Connection dropped — HaishinKit will retry")
                }
            default:
                break
            }
        }
    }
    #endif
}
