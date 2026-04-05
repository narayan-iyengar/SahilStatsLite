//
//  StreamingService.swift
//  SahilStatsLite
//
//  PURPOSE: Live YouTube streaming via RTMP using HaishinKit.
//           Receives composited CVPixelBuffer frames from RecordingManager
//           (scoreboard overlay already burned in) and pushes to YouTube.
//           Runs alongside AVAssetWriter — local HEVC recording unchanged.
//
//  SETUP:
//    1. HaishinKit added via SPM (done)
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
//  HaishinKit v3 notes:
//    RTMPStream is a Swift actor — all calls are async.
//    Use setVideoSettings() / setAudioSettings() (not direct property assignment).
//    append(_ CMSampleBuffer) auto-detects video vs audio from format description.
//

import Foundation
import AVFoundation
import VideoToolbox
import Combine
import HaishinKit
import RTMPHaishinKit

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

    static let streamKeyDefaultsKey = "SahilStats_YouTubeStreamKey"

    var savedStreamKey: String {
        get { UserDefaults.standard.string(forKey: Self.streamKeyDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.streamKeyDefaultsKey) }
    }

    private let rtmpURL = "rtmps://a.rtmp.youtube.com/live2"

    // nonisolated(unsafe): accessed from RecordingManager's background processingQueue.
    // Safe because writes only happen on @MainActor (startStream/stopStream),
    // reads only happen on background queue when isStreamingActive is true.
    nonisolated(unsafe) private var stream: RTMPStream?
    private var connection: RTMPConnection?
    private var statusTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func startStream() async {
        guard !savedStreamKey.isEmpty else {
            health = .failed("No stream key — add one in Settings")
            return
        }
        await _start(key: savedStreamKey)
    }

    func stopStream() async {
        statusTask?.cancel()
        statusTask = nil
        if let s = stream { try? await s.close() }
        try? await connection?.close()
        stream = nil
        connection = nil
        isStreaming = false
        health = .idle
        debugPrint("[Stream] Stopped")
    }

    // MARK: - Frame Injection
    // Called from RecordingManager's processingQueue (background thread).
    // CVPixelBuffer already has scoreboard overlay composited.

    nonisolated func appendVideoBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let stream else { return }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &fmt
        )
        guard let fmt else { return }

        var sb: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmt,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sb
        )
        if let sb {
            // RTMPStream is an actor — dispatch async, don't block the camera thread
            Task { await stream.append(sb) }
        }
    }

    nonisolated func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let stream else { return }
        Task { await stream.append(sampleBuffer) }
    }

    // MARK: - Private

    private func _start(key: String) async {
        health = .connecting
        isStreaming = true

        let conn = RTMPConnection()
        let strm = RTMPStream(connection: conn)

        // Configure H.264 — YouTube RTMP ingest requires H.264, not HEVC
        try? strm.setVideoSettings(VideoCodecSettings(
            videoSize: CGSize(width: 1920, height: 1080),
            bitRate: 6_000_000,
            profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
            maxKeyFrameIntervalDuration: 2    // YouTube: keyframe every 2 seconds
        ))
        try? strm.setAudioSettings(AudioCodecSettings(bitRate: 128_000))

        self.connection = conn
        self.stream = strm

        // Watch stream status
        statusTask = Task { [weak self] in
            for await status in await strm.status {
                guard let self else { break }
                await MainActor.run {
                    switch status.code {
                    case RTMPStream.Code.publishStart.rawValue:
                        self.health = .live
                        debugPrint("[Stream] 🔴 LIVE → YouTube")
                    case RTMPStream.Code.publishBadName.rawValue:
                        self.health = .failed("Invalid stream key")
                        debugPrint("[Stream] ❌ Invalid stream key")
                    default:
                        break
                    }
                }
            }
        }

        do {
            _ = try await conn.connect(rtmpURL)
            _ = try await strm.publish(key)
        } catch {
            health = .failed(error.localizedDescription)
            isStreaming = false
            self.stream = nil
            debugPrint("[Stream] ❌ \(error.localizedDescription)")
        }
    }
}
