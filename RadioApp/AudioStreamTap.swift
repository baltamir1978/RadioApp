import Foundation
import AVFoundation
import MediaToolbox

/// Passive tap on an AVPlayerItem that feeds decoded PCM to a handler without affecting playback.
/// Uses MTAudioProcessingTap so it works regardless of speaker/headphone/AirPlay output.
final class AudioStreamTap {
    typealias BufferHandler = (AVAudioPCMBuffer, AVAudioTime?) -> Void
    private weak var playerItem: AVPlayerItem?

    /// Installs the tap. Returns false if the item has no audio tracks yet.
    @discardableResult
    func install(on playerItem: AVPlayerItem, handler: @escaping BufferHandler) -> Bool {
        remove()

        let audioTracks = playerItem.tracks.filter { $0.assetTrack?.mediaType == .audio }
        guard !audioTracks.isEmpty else { return false }

        let context = TapContext(handler: handler)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: contextPtr,
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        var tapRef: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                        kMTAudioProcessingTapCreationFlag_PostEffects, &tapRef) == noErr,
              let tapObj = tapRef else {
            Unmanaged<TapContext>.fromOpaque(contextPtr).release()
            return false
        }
        let params = audioTracks.compactMap { track -> AVMutableAudioMixInputParameters? in
            guard let assetTrack = track.assetTrack else { return nil }
            let p = AVMutableAudioMixInputParameters(track: assetTrack)
            p.audioTapProcessor = tapObj
            return p
        }
        guard !params.isEmpty else { return false }

        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        playerItem.audioMix = mix
        self.playerItem = playerItem
        return true
    }

    func remove() {
        playerItem?.audioMix = nil
        playerItem = nil
    }
}

// MARK: - Context

private final class TapContext {
    let handler: AudioStreamTap.BufferHandler
    var format: AVAudioFormat?

    init(handler: @escaping AudioStreamTap.BufferHandler) {
        self.handler = handler
    }
}

// MARK: - C callbacks (non-capturing — must be global)

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    let ptr = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<TapContext>.fromOpaque(ptr).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
    let ptr = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<TapContext>.fromOpaque(ptr).takeUnretainedValue().format =
        AVAudioFormat(streamDescription: processingFormat)
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
    let ptr = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<TapContext>.fromOpaque(ptr).takeUnretainedValue().format = nil
}

private let tapProcess: MTAudioProcessingTapProcessCallback = {
    tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in

    // Pull audio through (pass-through — we don't modify it)
    MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)

    let ptr = MTAudioProcessingTapGetStorage(tap)
    let ctx = Unmanaged<TapContext>.fromOpaque(ptr).takeUnretainedValue()
    guard let format = ctx.format else { return }

    let frameCount = AVAudioFrameCount(numberFramesOut.pointee)
    guard frameCount > 0,
          let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
    pcmBuffer.frameLength = frameCount

    // Copy from tap's buffer list into the PCM buffer's own memory
    let src = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    let dst = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
    for i in 0..<min(src.count, dst.count) {
        guard let s = src[i].mData, let d = dst[i].mData else { continue }
        memcpy(d, s, Int(min(src[i].mDataByteSize, dst[i].mDataByteSize)))
    }

    ctx.handler(pcmBuffer, nil)
}
