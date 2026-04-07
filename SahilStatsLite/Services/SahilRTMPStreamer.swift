//
//  SahilRTMPStreamer.swift
//  SahilStatsLite
//
//  Custom RTMP streamer — zero HaishinKit dependency.
//  Handles full stack: TCP → RTMP handshake → connect → publish → FLV video/audio.
//
//  Why custom: HaishinKit's VideoCodec requires uncompressed BGRA at exact dimensions
//  and its configurationBox property doesn't support VTCompressionSession output format.
//  After extensive debugging, the 350-line custom implementation is more reliable and
//  has no hidden dependencies.
//

import Foundation
import Network
import AVFoundation
import VideoToolbox
import AudioToolbox

// MARK: - AMF0 Encoding

private struct AMF0 {
    static func string(_ s: String) -> Data {
        var d = Data([0x02]) + u16(UInt16(s.utf8.count)); d += s.utf8; return d
    }
    static func number(_ n: Double) -> Data {
        var v = n.bitPattern.bigEndian; return Data([0x00]) + Data(bytes: &v, count: 8)
    }
    static func null() -> Data { Data([0x05]) }
    static func object(_ pairs: [(String, Data)]) -> Data {
        var d = Data([0x03])
        for (k, v) in pairs { d += u16(UInt16(k.utf8.count)); d += k.utf8; d += v }
        return d + Data([0x00, 0x00, 0x09])
    }
    static func u16(_ v: UInt16) -> Data { Data([UInt8(v >> 8), UInt8(v & 0xFF)]) }
}

// MARK: - RTMP Chunk Encoding

private let kChunkSize = 128

private func chunk(csid: UInt8, type: UInt8, streamId: UInt32,
                   ts: UInt32, payload: Data) -> Data {
    var out = Data(); var off = 0
    while off < payload.count {
        let end = min(off + kChunkSize, payload.count)
        if off == 0 {
            let t = min(ts, 0xFFFFFF); let n = payload.count
            out += [csid,
                    UInt8((t>>16)&0xFF), UInt8((t>>8)&0xFF), UInt8(t&0xFF),
                    UInt8((n>>16)&0xFF), UInt8((n>>8)&0xFF), UInt8(n&0xFF),
                    type,
                    UInt8(streamId&0xFF), UInt8((streamId>>8)&0xFF),
                    UInt8((streamId>>16)&0xFF), UInt8((streamId>>24)&0xFF)]
        } else {
            out += [0xC0 | csid]
        }
        out += payload[off..<end]; off = end
    }
    return out
}

// MARK: - RTMP Commands

private func connectCmd(tcUrl: String) -> Data {
    chunk(csid: 3, type: 0x14, streamId: 0, ts: 0,
          payload: AMF0.string("connect") + AMF0.number(1) +
          AMF0.object([("app",      AMF0.string("live2")),
                       ("type",     AMF0.string("nonprivate")),
                       ("flashVer", AMF0.string("FMLE/3.0 (compatible; FMSc/1.0)")),
                       ("tcUrl",    AMF0.string(tcUrl))]))
}

private func createStreamCmd() -> Data {
    chunk(csid: 3, type: 0x14, streamId: 0, ts: 0,
          payload: AMF0.string("createStream") + AMF0.number(2) + AMF0.null())
}

private func publishCmd(key: String, sid: UInt32) -> Data {
    chunk(csid: 8, type: 0x14, streamId: sid, ts: 0,
          payload: AMF0.string("publish") + AMF0.number(0) + AMF0.null() +
          AMF0.string(key) + AMF0.string("live"))
}

private func metadataCmd(sid: UInt32) -> Data {
    chunk(csid: 4, type: 0x12, streamId: sid, ts: 0,
          payload: AMF0.string("@setDataFrame") + AMF0.string("onMetaData") +
          AMF0.object([("duration",        AMF0.number(0)),
                       ("width",           AMF0.number(1920)),
                       ("height",          AMF0.number(1080)),
                       ("videocodecid",    AMF0.number(7)),
                       ("videodatarate",   AMF0.number(6000)),
                       ("framerate",       AMF0.number(30)),
                       ("audiocodecid",    AMF0.number(10)),
                       ("audiodatarate",   AMF0.number(128)),
                       ("audiosamplerate", AMF0.number(44100))]))
}

// MARK: - FLV Video

private func avcSeqHeader(fd: CMVideoFormatDescription, ts: UInt32, sid: UInt32) -> Data? {
    var count = 0; var nal: Int32 = 0
    guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        fd, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil,
        parameterSetCountOut: &count, nalUnitHeaderLengthOut: &nal) == noErr,
          count >= 2 else { return nil }
    var sp: UnsafePointer<UInt8>?; var sl = 0
    var pp: UnsafePointer<UInt8>?; var pl = 0
    guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            fd, parameterSetIndex: 0,
            parameterSetPointerOut: &sp, parameterSetSizeOut: &sl,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
          CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            fd, parameterSetIndex: 1,
            parameterSetPointerOut: &pp, parameterSetSizeOut: &pl,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
          let sps = sp, sl >= 4, let pps = pp, pl > 0 else { return nil }
    var avcc = Data([0x01, sps[1], sps[2], sps[3], 0xFF, 0xE1])
    avcc += [UInt8((sl>>8)&0xFF), UInt8(sl&0xFF)] + Data(bytes: sps, count: sl)
    avcc += [0x01, UInt8((pl>>8)&0xFF), UInt8(pl&0xFF)] + Data(bytes: pps, count: pl)
    return chunk(csid: 6, type: 0x09, streamId: sid, ts: ts,
                 payload: Data([0x17, 0x00, 0x00, 0x00, 0x00]) + avcc)
}

private func avcFrame(sb: CMSampleBuffer, ts: UInt32, sid: UInt32) -> Data? {
    guard let block = sb.dataBuffer else { return nil }
    var len = 0; var ptr: UnsafeMutablePointer<Int8>?
    guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                      totalLengthOut: &len, dataPointerOut: &ptr) == noErr,
          let p = ptr, len > 0 else { return nil }
    let isKey = !((sb.attachments(propagate: false)
        .first?[CMSampleBufferAttachmentKey.notSync] as? Bool) ?? false)
    var payload = Data([isKey ? 0x17 : 0x27, 0x01, 0x00, 0x00, 0x00])
    payload += Data(bytes: p, count: len)
    return chunk(csid: 6, type: 0x09, streamId: sid, ts: ts, payload: payload)
}

// MARK: - FLV Audio (AAC)

private func aacSeqHeader(sid: UInt32) -> Data {
    // AAC-LC, 44100 Hz, stereo: AudioSpecificConfig = 0x12 0x10
    chunk(csid: 4, type: 0x08, streamId: sid, ts: 0,
          payload: Data([0xAF, 0x00, 0x12, 0x10]))
}

private func aacFrame(_ data: Data, ts: UInt32, sid: UInt32) -> Data {
    chunk(csid: 4, type: 0x08, streamId: sid, ts: ts,
          payload: Data([0xAF, 0x01]) + data)
}

// MARK: - Streamer

final class SahilRTMPStreamer {

    private let host = "a.rtmp.youtube.com"
    private let port: UInt16 = 1935
    private let ioQueue = DispatchQueue(label: "SahilRTMP.io", qos: .userInitiated)

    nonisolated(unsafe) private var conn: NWConnection?
    nonisolated(unsafe) private var streamId: UInt32 = 1
    nonisolated(unsafe) private var running = false

    // Video
    nonisolated(unsafe) private var vtSession: VTCompressionSession?
    nonisolated(unsafe) private var frameCount: Int64 = 0
    nonisolated(unsafe) private var videoStart: CMTime = .invalid
    nonisolated(unsafe) private var sentVideoSeqHdr = false

    // Audio
    nonisolated(unsafe) private var audioConverter: AVAudioConverter?
    nonisolated(unsafe) private var audioStart: CMTime = .invalid
    nonisolated(unsafe) private var sentAudioSeqHdr = false

    var onLive: (() -> Void)?
    var onFailed: ((String) -> Void)?

    // MARK: - Start

    func start(streamKey: String) {
        running = false
        let c = NWConnection(host: NWEndpoint.Host(host),
                             port: NWEndpoint.Port(integerLiteral: port),
                             using: .tcp)
        conn = c
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state { self.ioQueue.async { self.onConnected(c, key: streamKey) } }
            else if case .failed(let e) = state { self.fail("TCP: \(e)") }
        }
        c.start(queue: ioQueue)
    }

    func stop() {
        running = false
        conn?.cancel(); conn = nil
        destroyVT()
        audioConverter = nil; audioStart = .invalid; sentAudioSeqHdr = false
    }

    // MARK: - Frame Injection

    func appendVideo(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard running else { return }
        if vtSession == nil {
            setupVT(CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer))
        }
        guard let session = vtSession else { return }
        if videoStart == .invalid { videoStart = timestamp }
        frameCount += 1
        let props: CFDictionary? = frameCount % 60 == 1 ?
            [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer,
            presentationTimeStamp: timestamp,
            duration: CMTime(value: 1, timescale: 30),
            frameProperties: props, infoFlagsOut: nil,
            outputHandler: { [weak self] status, _, sb in
                guard let self, let sb, status == noErr, self.running else { return }
                self.sendVideo(sb)
            })
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard running, sentAudioSeqHdr else { return }
        encodeAudio(sampleBuffer)
    }

    // MARK: - Protocol

    private func onConnected(_ c: NWConnection, key: String) {
        do {
            // Handshake
            var c0c1 = Data([0x03]) + Data(repeating: 0, count: 8)
            c0c1 += Data((0..<1528).map { _ in UInt8.random(in: 0...255) })
            sendSync(c, data: c0c1)
            let s012 = recvSync(c, length: 1 + 1536 + 1536)
            sendSync(c, data: Data(s012[1..<1537])) // C2 = S1

            // Connect
            sendSync(c, data: connectCmd(tcUrl: "rtmp://\(host)/live2"))
            waitFor(c, tag: "_result")

            // createStream
            sendSync(c, data: createStreamCmd())
            waitFor(c, tag: "_result")

            // publish
            sendSync(c, data: publishCmd(key: key, sid: streamId))
            waitFor(c, tag: "NetStream.Publish.Start")

            // metadata + audio seq header
            sendSync(c, data: metadataCmd(sid: streamId))
            sendSync(c, data: aacSeqHeader(sid: streamId))
            sentAudioSeqHdr = true
            running = true
            debugPrint("[SahilRTMP] ✅ LIVE — streaming to YouTube")
            DispatchQueue.main.async { self.onLive?() }

            // drain incoming data forever
            while running { _ = recvSync(c, length: 1) }
        } catch {
            fail("\(error)")
        }
    }

    // MARK: - Video

    private func sendVideo(_ sb: CMSampleBuffer) {
        guard let c = conn else { return }
        let ts = msSince(sb.presentationTimeStamp, start: videoStart)

        if !sentVideoSeqHdr, let fd = sb.formatDescription as? CMVideoFormatDescription {
            sentVideoSeqHdr = true
            if let data = avcSeqHeader(fd: fd, ts: ts, sid: streamId) {
                sendAsync(c, data: data)
                debugPrint("[SahilRTMP] AVC sequence header sent")
            }
        }
        if let data = avcFrame(sb: sb, ts: ts, sid: streamId) {
            sendAsync(c, data: data)
        }
    }

    // MARK: - Audio

    private func encodeAudio(_ sb: CMSampleBuffer) {
        guard let c = conn else { return }
        guard let inputFmt = sb.formatDescription.flatMap({ AVAudioFormat(cmAudioFormatDescription: $0) }) else { return }

        if audioConverter == nil {
            let aacSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            guard let aacFmt = AVAudioFormat(settings: aacSettings),
                  let conv = AVAudioConverter(from: inputFmt, to: aacFmt) else { return }
            audioConverter = conv
            debugPrint("[SahilRTMP] AAC converter ready")
        }
        guard let conv = audioConverter else { return }
        if audioStart == .invalid { audioStart = sb.presentationTimeStamp }

        let n = CMSampleBufferGetNumSamples(sb)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inputFmt, frameCapacity: AVAudioFrameCount(n)),
              let outBuf = AVAudioCompressedBuffer(format: conv.outputFormat,
                                                   packetCapacity: 1, maximumPacketSize: 1024) else { return }
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sb, at: 0, frameCount: Int32(n), into: inBuf.mutableAudioBufferList) == noErr else { return }
        inBuf.frameLength = AVAudioFrameCount(n)
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            status.pointee = .haveData; return inBuf
        }
        guard err == nil, outBuf.byteLength > 0 else { return }
        let ts = msSince(sb.presentationTimeStamp, start: audioStart)
        sendAsync(c, data: aacFrame(Data(bytes: outBuf.data, count: Int(outBuf.byteLength)),
                                     ts: ts, sid: streamId))
    }

    // MARK: - VT

    private func setupVT(_ width: Int, _ height: Int) {
        let w = min(width, 1920), h = min(height, 1080)
        var s: VTCompressionSession?
        VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                   width: Int32(w), height: Int32(h),
                                   codecType: kCMVideoCodecType_H264,
                                   encoderSpecification: nil, imageBufferAttributes: nil,
                                   compressedDataAllocator: nil, outputCallback: nil,
                                   refcon: nil, compressionSessionOut: &s)
        guard let session = s else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime,                    value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,              value: NSNumber(value: 6_000_000))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 2.0))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,                value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,        value: kCFBooleanFalse)
        VTCompressionSessionPrepareToEncodeFrames(session)
        vtSession = session
        debugPrint("[SahilRTMP] VT ready \(w)×\(h)")
    }

    private func destroyVT() {
        if let s = vtSession { VTCompressionSessionInvalidate(s); vtSession = nil }
        frameCount = 0; videoStart = .invalid; sentVideoSeqHdr = false
    }

    // MARK: - Helpers

    private func msSince(_ t: CMTime, start: CMTime) -> UInt32 {
        guard start != .invalid else { return 0 }
        return UInt32(max(0, (t.seconds - start.seconds) * 1000))
    }

    private func fail(_ msg: String) {
        debugPrint("[SahilRTMP] ❌ \(msg)")
        running = false
        DispatchQueue.main.async { self.onFailed?(msg) }
    }

    private func sendAsync(_ c: NWConnection, data: Data) {
        c.send(content: data, completion: .idempotent)
    }

    private func sendSync(_ c: NWConnection, data: Data) {
        let sem = DispatchSemaphore(value: 0)
        c.send(content: data, completion: .contentProcessed { _ in sem.signal() })
        sem.wait()
    }

    private func recvSync(_ c: NWConnection, length: Int) -> Data {
        var result = Data()
        var remaining = length
        while remaining > 0 {
            let sem = DispatchSemaphore(value: 0)
            c.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, _, _ in
                if let d = data, !d.isEmpty { result += d; remaining -= d.count }
                else { remaining = 0 }
                sem.signal()
            }
            sem.wait()
        }
        return result
    }

    private func waitFor(_ c: NWConnection, tag: String) {
        var buf = Data()
        let target = tag.data(using: .utf8)!
        while !buf.contains(target) {
            let chunk = recvSync(c, length: 1)
            if chunk.isEmpty { break }
            buf += chunk
            if buf.count > 65536 { buf = Data(buf.suffix(32768)) }
        }
    }
}

private extension Data {
    func contains(_ other: Data) -> Bool {
        guard other.count <= count else { return false }
        return (0...(count - other.count)).contains { self[$0..<($0 + other.count)] == other }
    }
}
