import Foundation
import AudioToolbox
import AVFoundation

/// Independently fetches a radio stream over its own HTTP connection, decodes the compressed
/// audio (MP3 / AAC) to PCM, and hands the PCM to a callback — without AVPlayer and regardless
/// of the audio output route.
///
/// This is the recognition path for stations whose delivery (ad-handler redirect chains,
/// tokenized / HLS endpoints, e.g. Kiss FM) starves the passive player tap, *and* where the
/// microphone has no acoustic path: CarPlay, AirPlay, wired/Bluetooth headphones. URLSession
/// follows the redirect chain and mints the token for us, so we just feed the resulting bytes
/// to AudioFileStream → AudioConverter → ShazamKit.
///
/// Two non-obvious requirements make `AudioConverterFillComplexBuffer` behave with a live MP3
/// stream, both verified against the real Kiss FM feed:
///  1. The output `AVAudioPCMBuffer` reports a zero-size buffer list until `frameLength` is set,
///     so we set `frameLength = frameCapacity` *before* the fill call (else it returns -50).
///  2. The converter latches into end-of-stream the moment our input callback returns 0 packets.
///     So we keep a persistent packet queue, request exactly `packets * framesPerPacket` frames,
///     and always hold one packet in reserve — the input callback never has to return 0.
nonisolated final class StreamDecoder: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias PCMHandler = @Sendable (AVAudioPCMBuffer) -> Void

    private let url: URL
    private let handler: PCMHandler

    private var session: URLSession?
    private var task: URLSessionDataTask?

    private var streamID: AudioFileStreamID?
    private var converter: AudioConverterRef?
    private var sourceFormat = AudioStreamBasicDescription()
    private var outputFormat: AVAudioFormat?
    private var fileTypeHint: AudioFileTypeID = 0

    private let stateLock = NSLock()
    private var _cancelled = false
    private var cancelled: Bool { stateLock.lock(); defer { stateLock.unlock() }; return _cancelled }

    // Persistent queue of compressed packets awaiting decode. Offsets in `descs` are absolute
    // into `data`. Bounded in practice: the decoder lives only for one recognition window.
    private var data = Data()
    private var descs: [AudioStreamPacketDescription] = []
    private var consumed = 0
    private var dataBase: UnsafeRawPointer?     // valid only inside `drain`
    private var scratch: [AudioStreamPacketDescription] = []

    init(url: URL, handler: @escaping PCMHandler) {
        self.url = url
        self.handler = handler
        super.init()
    }

    func start() {
        var request = URLRequest(url: url)
        request.setValue("RadioApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Callbacks for a single task are delivered serially, so AudioFileStream / AudioConverter
        // and the packet queue are only ever touched from one thread at a time.
        let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session = s
        let t = s.dataTask(with: request)
        task = t
        t.resume()
    }

    func stop() {
        stateLock.lock(); _cancelled = true; stateLock.unlock()
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let mime = response.mimeType?.lowercased() {
            if mime.contains("aac") {
                fileTypeHint = kAudioFileAAC_ADTSType
            } else if mime.contains("mpeg") || mime.contains("mp3") {
                fileTypeHint = kAudioFileMP3Type
            }
        }
        completionHandler(cancelled ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !cancelled else { return }
        if streamID == nil {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            AudioFileStreamOpen(ctx, streamPropertyProc, streamPacketsProc, fileTypeHint, &streamID)
        }
        guard let streamID else { return }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            AudioFileStreamParseBytes(streamID, UInt32(raw.count), base, [])
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let converter { AudioConverterDispose(converter); self.converter = nil }
        if let streamID { AudioFileStreamClose(streamID); self.streamID = nil }
    }

    // MARK: - AudioFileStream callbacks

    fileprivate func onProperty(_ streamID: AudioFileStreamID, _ propertyID: AudioFileStreamPropertyID) {
        switch propertyID {
        case kAudioFileStreamProperty_DataFormat:
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            AudioFileStreamGetProperty(streamID, kAudioFileStreamProperty_DataFormat, &size, &sourceFormat)
        case kAudioFileStreamProperty_ReadyToProducePackets:
            setupConverter()
        default:
            break
        }
    }

    private func setupConverter() {
        guard converter == nil, sourceFormat.mSampleRate > 0 else { return }
        let channels = max(1, sourceFormat.mChannelsPerFrame)
        guard let out = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: sourceFormat.mSampleRate,
                                      channels: AVAudioChannelCount(channels),
                                      interleaved: false) else { return }
        outputFormat = out
        var dst = out.streamDescription.pointee
        var conv: AudioConverterRef?
        if AudioConverterNew(&sourceFormat, &dst, &conv) == noErr {
            converter = conv
        }
    }

    fileprivate func onPackets(_ numberBytes: UInt32, _ numberPackets: UInt32,
                               _ inputData: UnsafeRawPointer,
                               _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard !cancelled else { return }
        if converter == nil { setupConverter() }
        guard converter != nil, let descsPtr = packetDescriptions else { return }

        let baseOffset = data.count
        data.append(Data(bytes: inputData, count: Int(numberBytes)))
        for i in 0..<Int(numberPackets) {
            var d = descsPtr[i]
            d.mStartOffset += Int64(baseOffset)
            descs.append(d)
        }
        drain()
    }

    private func drain() {
        guard let converter, let outFmt = outputFormat else { return }
        let framesPerPacket = sourceFormat.mFramesPerPacket > 0 ? Int(sourceFormat.mFramesPerPacket) : 1152
        let reserve = 1            // keep a packet back so `provideInput` never returns 0 (EOS latch)
        let maxPacketsPerCall = 8
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        data.withUnsafeBytes { raw in
            dataBase = raw.baseAddress
            defer { dataBase = nil }
            while descs.count - consumed > reserve {
                let packets = min(descs.count - consumed - reserve, maxPacketsPerCall)
                let capacity = AVAudioFrameCount(packets * framesPerPacket)
                guard let pcm = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: capacity) else { break }
                pcm.frameLength = capacity
                var io = UInt32(capacity)
                let before = consumed
                let status = AudioConverterFillComplexBuffer(converter, converterInputProc, ctx,
                                                            &io, pcm.mutableAudioBufferList, nil)
                if io > 0 {
                    pcm.frameLength = io
                    handler(pcm)
                }
                if status != noErr || io == 0 || consumed == before { break }
            }
        }
    }

    fileprivate func provideInput(_ ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
                                  _ ioData: UnsafeMutablePointer<AudioBufferList>,
                                  _ outDesc: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?) -> OSStatus {
        let remaining = descs.count - consumed
        guard remaining > 0, let base = dataBase else {
            ioNumberDataPackets.pointee = 0
            return noErr
        }
        let n = min(Int(ioNumberDataPackets.pointee), remaining)
        let firstOffset = Int(descs[consumed].mStartOffset)
        let last = consumed + n - 1
        let lastEnd = Int(descs[last].mStartOffset) + Int(descs[last].mDataByteSize)

        let abl = UnsafeMutableAudioBufferListPointer(ioData)
        abl[0].mNumberChannels = sourceFormat.mChannelsPerFrame
        abl[0].mData = UnsafeMutableRawPointer(mutating: base.advanced(by: firstOffset))
        abl[0].mDataByteSize = UInt32(lastEnd - firstOffset)

        if let outDesc {
            // Offsets must be relative to the buffer we just handed over.
            scratch.removeAll(keepingCapacity: true)
            for i in 0..<n {
                var d = descs[consumed + i]
                d.mStartOffset -= Int64(firstOffset)
                scratch.append(d)
            }
            scratch.withUnsafeMutableBufferPointer { outDesc.pointee = $0.baseAddress }
        }
        consumed += n
        ioNumberDataPackets.pointee = UInt32(n)
        return noErr
    }
}

// MARK: - C callbacks (non-capturing — must be global)

// These are stateless C function pointers; they must be callable from the audio / URLSession
// background threads, so they opt out of the project's default main-actor isolation.
nonisolated(unsafe) private let streamPropertyProc: AudioFileStream_PropertyListenerProc = { clientData, streamID, propertyID, _ in
    Unmanaged<StreamDecoder>.fromOpaque(clientData).takeUnretainedValue().onProperty(streamID, propertyID)
}

nonisolated(unsafe) private let streamPacketsProc: AudioFileStream_PacketsProc = { clientData, numberBytes, numberPackets, inputData, packetDescriptions in
    Unmanaged<StreamDecoder>.fromOpaque(clientData).takeUnretainedValue()
        .onPackets(numberBytes, numberPackets, inputData, packetDescriptions)
}

nonisolated(unsafe) private let converterInputProc: AudioConverterComplexInputDataProc = { _, ioNumberDataPackets, ioData, outDataPacketDescription, context in
    guard let context else {
        ioNumberDataPackets.pointee = 0
        return noErr
    }
    return Unmanaged<StreamDecoder>.fromOpaque(context).takeUnretainedValue()
        .provideInput(ioNumberDataPackets, ioData, outDataPacketDescription)
}
