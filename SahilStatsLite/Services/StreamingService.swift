//
//  StreamingService.swift
//  SahilStatsLite
//
//  PURPOSE: Live YouTube streaming via RTMP using HaishinKit.
//
//  Architecture:
//   - RTMP transport: HaishinKit (RTMPConnection/RTMPStream) — patched in DerivedData:
//       1. Minimal FMLE-style CONNECT command (4 fields, no Enhanced RTMP)
//       2. No SetChunkSize(8192) — YouTube rejects large chunk negotiation
//       3. makeMetadata() includes video fields when videoSettings.bitRate > 0
//   - Video encoding: VTCompressionSession (H.264 High, 6Mbps, 1080p)
//     Pre-encoded sample buffers go through HaishinKit's compressed path (isCompressed==true)
//     which sends the AVC sequence header + NALUs correctly without going through VideoCodec.
//   - Audio encoding: HaishinKit's internal AAC encoder (PCM → AAC 128kbps)
//
//  SETUP:
//    Settings → YouTube Live → stream key + toggle ON
//
//  YOUTUBE REQUIREMENTS:
//    Endpoint: rtmp://a.rtmp.youtube.com/live2
//    Codec:    H.264 High profile, keyframe every 2s, 6 Mbps
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

    static let streamKeyDefaultsKey        = "SahilStats_YouTubeStreamKey"
    static let streamingEnabledDefaultsKey = "SahilStats_StreamingEnabled"

    var savedStreamKey: String {
        get { UserDefaults.standard.string(forKey: Self.streamKeyDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.streamKeyDefaultsKey) }
    }

    var streamingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.streamingEnabledDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.streamingEnabledDefaultsKey) }
    }

    // Plain RTMP port 1935 — no TLS cert issues (iOS 26 NWConnection blocks RTMPS here)
    private let rtmpURL = "rtmp://a.rtmp.youtube.com/live2"

    nonisolated(unsafe) private var stream: RTMPStream?
    private var connection: RTMPConnection?
    private var statusTask: Task<Void, Never>?

    // VTCompressionSession encodes 4K overlay frames → H.264 at 1080p
    nonisolated(unsafe) private var vtSession: VTCompressionSession?
    nonisolated(unsafe) private var frameCount: Int64 = 0

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
        destroyCompressor()
        isStreaming = false
        health = .idle
    }

    // MARK: - Frame Injection

    /// Video: encode to H.264 via VTCompressionSession → append compressed buffer to HaishinKit.
    /// HaishinKit's compressed path (isCompressed==true) handles AVC sequence header + FLV framing.
    nonisolated func appendVideoBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard stream != nil else { return }

        if vtSession == nil {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            setupCompressor(width: w, height: h)
        }
        guard let session = vtSession else { return }

        frameCount += 1
        let isKeyFrame = frameCount % 60 == 1

        var frameProps: CFDictionary? = nil
        if isKeyFrame {
            frameProps = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        }

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: timestamp,
            duration: CMTime(value: 1, timescale: 30),
            frameProperties: frameProps,
            infoFlagsOut: nil,
            outputHandler: { [weak self] status, _, sampleBuffer in
                guard let self,
                      let sb = sampleBuffer,
                      status == noErr else { return }
                Task { await self.stream?.append(sb) }
            }
        )
    }

    /// Audio: PCM → AAC via HaishinKit's internal encoder
    nonisolated func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let stream else { return }
        Task { await stream.append(sampleBuffer) }
    }

    // MARK: - VTCompressionSession (encodes 4K input → 1080p H.264)

    nonisolated private func setupCompressor(width: Int, height: Int) {
        let outW = min(width, 1920)
        let outH = min(height, 1080)

        var session: VTCompressionSession?
        VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(outW),
            height: Int32(outH),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard let session else { return }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime,                    value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,              value: NSNumber(value: 6_000_000))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 2.0))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,                value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,        value: kCFBooleanFalse)

        VTCompressionSessionPrepareToEncodeFrames(session)
        vtSession = session
        debugPrint("[Stream] VT H.264 encoder ready (\(outW)×\(outH))")
    }

    nonisolated private func destroyCompressor() {
        if let session = vtSession {
            VTCompressionSessionInvalidate(session)
            vtSession = nil
        }
        frameCount = 0
    }

    // MARK: - HaishinKit RTMP

    private func _start(key: String) async {
        health = .connecting
        isStreaming = true

        let conn = RTMPConnection()
        let strm = RTMPStream(connection: conn)

        self.connection = conn

        statusTask = Task { [weak self] in
            for await status in await strm.status {
                guard let self else { break }
                debugPrint("[Stream] STATUS code=\(status.code) level=\(status.level)")
                await MainActor.run {
                    switch status.code {
                    case RTMPStream.Code.publishStart.rawValue:
                        self.health = .live
                        debugPrint("[Stream] 🔴 LIVE → YouTube")
                    case RTMPStream.Code.publishBadName.rawValue:
                        self.health = .failed("Invalid stream key")
                    default:
                        break
                    }
                }
            }
        }

        do {
            debugPrint("[Stream] Connecting to \(rtmpURL)...")
            _ = try await conn.connect(rtmpURL)
            debugPrint("[Stream] Connected")

            // Configure settings BEFORE publish so @setDataFrame onMetaData fires with
            // correct video fields. makeMetadata() (patched in DerivedData) gates video
            // metadata on outgoing.videoSettings.bitRate > 0.
            try? await strm.setVideoSettings(VideoCodecSettings(
                videoSize: CGSize(width: 1920, height: 1080),
                bitRate: 6_000_000))
            try? await strm.setAudioSettings(AudioCodecSettings(bitRate: 128_000))

            debugPrint("[Stream] Publishing with key \(key.prefix(8))...")
            _ = try await strm.publish(key)
            debugPrint("[Stream] Publish accepted — metadata sent with video fields")

            // Expose stream after full setup — VT encoder starts on first frame
            self.stream = strm
            debugPrint("[Stream] 🔴 stream live — VT encoding + HaishinKit transport")

        } catch let e as RTMPConnection.Error {
            let detail: String
            switch e {
            case .invalidState:              detail = "RTMPConn.invalidState"
            case .unsupportedCommand(let c): detail = "RTMPConn.unsupportedCommand(\(c))"
            case .connectionTimedOut:        detail = "RTMPConn.connectionTimedOut"
            case .socketErrorOccurred(let s): detail = "RTMPConn.socketError: \(s?.localizedDescription ?? "nil")"
            case .requestTimedOut:           detail = "RTMPConn.requestTimedOut"
            case .requestFailed(let r):
                let s = r.status
                detail = "RTMPConn.requestFailed code=\(s?.code ?? "?") desc=\(s?.description ?? "?")"
            }
            health = .failed(detail)
            isStreaming = false
            self.stream = nil
            destroyCompressor()
            debugPrint("[Stream] ❌ \(detail)")
        } catch {
            let detail = "unexpected: \(error)"
            health = .failed(detail)
            isStreaming = false
            self.stream = nil
            destroyCompressor()
            debugPrint("[Stream] ❌ \(detail)")
        }
    }
}
