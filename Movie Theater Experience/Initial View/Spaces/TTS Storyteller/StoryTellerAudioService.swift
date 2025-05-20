//
//  StorytellerAudioService.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 6/21/25.
//  Re-written 24 Jun 25 to provide fast 128-bucket spectrum data.
//

import Foundation
import AVFoundation
import Accelerate
import CoreMedia
import AVKit
import os.lock               // OSAllocatedUnfairLock

// MARK: - Main service -------------------------------------------------------

class StorytellerAudioService {

    // MARK: - Public ---------------------------------------------------------
    let player = AVPlayer()

    /// Latest microphone / narration RMS (≈ 0‥1). UI pulls via `getCurrentLevel()`.
    func getCurrentLevel()  -> Float      { levelLock.withLock { currentLevel  } }
    /// 128-bucket instantaneous spectrum. UI pulls via `getSpectrum()`.
    func getSpectrum()      -> [Float]    { specLock.withLock  { latestSpectrum } }

    
    func stop() {
        player.pause()

        // Detach the tap •before• StorytellerAudioService dies
        if let item = player.currentItem {
            item.audioMix = nil        // this invalidates the tap
        }
        tap = nil
        player.replaceCurrentItem(with: nil)
    }

    deinit {        // belt-and-suspenders
        stop()
    }
    
    /// Call once with the narration URL.
    func loadMedia(from url: URL) {
        let asset = AVURLAsset(url: url)

        asset.loadTracks(withMediaType: .audio) { [weak self] tracks, error in
            guard let self = self, let track = tracks?.first else {
                print("No audio track: \(error?.localizedDescription ?? "(unknown)")")
                return
            }

            let item       = AVPlayerItem(asset: asset)
            let clientInfo = Unmanaged.passUnretained(self).toOpaque()

            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: clientInfo,
                init: tapInit,
                finalize: tapFinalize,
                prepare: tapPrepare,
                unprepare: tapUnprepare,
                process: tapProcess
            )

            var unmanaged: Unmanaged<MTAudioProcessingTap>?
            let err = MTAudioProcessingTapCreate(
                kCFAllocatorDefault,
                &callbacks,
                kMTAudioProcessingTapCreationFlag_PostEffects,
                &unmanaged
            )
            guard err == noErr, let u = unmanaged else {
                print("Audio-tap creation failed: \(err)")
                DispatchQueue.main.async { self.player.replaceCurrentItem(with: item) }
                return
            }

            self.tap = u.takeRetainedValue()

            let mix   = AVMutableAudioMix()
            let input = AVMutableAudioMixInputParameters(track: track)
            input.audioTapProcessor = self.tap
            mix.inputParameters = [input]
            item.audioMix       = mix

            DispatchQueue.main.async { self.player.replaceCurrentItem(with: item) }
        }
    }

    // MARK: - Internal / storage --------------------------------------------
    /// Size of the bar array exposed to the UI.
    static let bucketCount = 128

    private var tap: MTAudioProcessingTap?

    // — level —
    private let levelLock = OSAllocatedUnfairLock()
    private var currentLevel: Float = 0
    fileprivate func setCurrentLevel(_ v: Float) { levelLock.withLock { currentLevel = v } }

    // — spectrum —
    private let specLock  = OSAllocatedUnfairLock()
    private var latestSpectrum = [Float](repeating: 0, count: bucketCount)
    fileprivate func setSpectrum(_ s: [Float])   { specLock.withLock  { latestSpectrum = s } }
}

// MARK: - MTAudioProcessingTap callbacks -------------------------------------

/// Store the service pointer
private let tapInit: MTAudioProcessingTapInitCallback = { tap, clientInfo, storage in
    storage.pointee = clientInfo
}
private let tapFinalize:   MTAudioProcessingTapFinalizeCallback   = { _ in }
private let tapPrepare:    MTAudioProcessingTapPrepareCallback    = { _,_,_ in }
private let tapUnprepare:  MTAudioProcessingTapUnprepareCallback  = { _ in }

/// Core processing: copy frames, compute RMS & spectrum buckets
private let tapProcess: MTAudioProcessingTapProcessCallback = { (
    tap,
    frameCount,
    flags,
    bufferListInOut,
    frameCountOut,
    flagsOut
) in
    // 1. Get the service instance
    let service = Unmanaged<StorytellerAudioService>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap))
        .takeUnretainedValue()

    // 2. Ask the tap for source audio
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        frameCount,
        bufferListInOut,
        flagsOut,
        nil,
        frameCountOut
    )
    if status != noErr { return }

    // 3. Work with the first buffer (mono or left channel)
    let abl       = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    guard let raw = abl.first?.mData else { return }
    let samples   = raw.assumingMemoryBound(to: Float.self)
    let frames    = Int(frameCount)

    // --- 3a. RMS for overall level ----------------------------------------
    var rms: Float = 0
    vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frames))
    let scaled = pow(rms, 0.5) * 2         // tweak scalar for UI comfort
    service.setCurrentLevel(scaled)

    // --- 3b. 128-bucket “spectrum like” snapshot --------------------------
    let buckets = StorytellerAudioService.bucketCount
    var out = [Float](repeating: 0, count: buckets)

    let stride = max(1, frames / buckets)
    for i in 0..<buckets {
        // pick one sample per slice, take abs for magnitude
        let idx          = i * stride
        out[i]           = fabsf(samples[idx])
    }
    service.setSpectrum(out)
}
