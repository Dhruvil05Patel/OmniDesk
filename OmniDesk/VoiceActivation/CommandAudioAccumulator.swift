//
//  CommandAudioAccumulator.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 02/11/26.
//

import AVFoundation
import Foundation
import os

/// High-performance, lock-guarded in-memory PCM audio accumulator.
/// Receives audio buffers from hardware input taps, downsamples them to standard 16,000 Hz Float32 mono PCM,
/// and enforces strict memory bounds (default: 10.0s max command duration = 160,000 samples = ~640 KB in RAM).
public final class CommandAudioAccumulator: @unchecked Sendable {
    
    public let targetSampleRate: Double
    public let maxDurationSeconds: Double
    public let maxSampleCapacity: Int
    
    private var samples: [Float]
    private var lock = os_unfair_lock()
    
    /// Initializes an accumulator with a target sample rate and maximum duration cap.
    /// - Parameters:
    ///   - targetSampleRate: Desired sample rate for model tokenization (default: 16,000 Hz).
    ///   - maxDurationSeconds: Maximum allowable speech command duration (default: 10.0 seconds).
    public init(targetSampleRate: Double = 16000.0, maxDurationSeconds: Double = 10.0) {
        self.targetSampleRate = targetSampleRate
        self.maxDurationSeconds = maxDurationSeconds
        self.maxSampleCapacity = max(1024, Int(targetSampleRate * maxDurationSeconds))
        self.samples = []
        self.samples.reserveCapacity(self.maxSampleCapacity)
    }
    
    /// Appends an `AVAudioPCMBuffer`, converting from hardware input sample rate to target 16kHz mono.
    public func append(buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0,
              buffer.audioBufferList.pointee.mBuffers.mDataByteSize > 0,
              let channelData = buffer.floatChannelData?[0] else {
            return
        }
        
        let inputCount = Int(buffer.frameLength)
        let inputRate = buffer.format.sampleRate
        
        append(samples: channelData, count: inputCount, inputSampleRate: inputRate)
    }
    
    /// Appends raw float samples with resample conversion.
    public func append(samples rawPtr: UnsafePointer<Float>, count: Int, inputSampleRate: Double) {
        guard count > 0 else { return }
        
        let converted = resampleToTarget(rawPtr: rawPtr, count: count, from: inputSampleRate, to: targetSampleRate)
        guard !converted.isEmpty else { return }
        
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let remaining = maxSampleCapacity - samples.count
        if remaining > 0 {
            let toAppend = min(remaining, converted.count)
            samples.append(contentsOf: converted[0..<toAppend])
        }
    }
    
    /// Appends an array of Float samples with resample conversion.
    public func append(samples array: [Float], inputSampleRate: Double) {
        array.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                append(samples: base, count: ptr.count, inputSampleRate: inputSampleRate)
            }
        }
    }
    
    /// Extracts all currently accumulated 16kHz audio samples and clears the buffer.
    public func extractAndReset() -> [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let result = samples
        samples.removeAll(keepingCapacity: true)
        return result
    }
    
    /// Returns the current number of accumulated 16kHz samples.
    public var currentSampleCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return samples.count
    }
    
    /// Returns the current accumulated audio duration in seconds.
    public var currentDuration: Double {
        return Double(currentSampleCount) / targetSampleRate
    }
    
    /// Resets and clears all accumulated samples immediately.
    public func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        samples.removeAll(keepingCapacity: true)
    }
    
    // MARK: - Resampling Helper
    
    /// High-performance linear interpolation resampler converting arbitrary input sample rates to target 16kHz.
    public func resampleToTarget(
        rawPtr: UnsafePointer<Float>,
        count: Int,
        from inputRate: Double,
        to outputRate: Double
    ) -> [Float] {
        guard count > 0 else { return [] }
        
        // Exact match fast path
        if abs(inputRate - outputRate) < 1.0 {
            return Array(UnsafeBufferPointer(start: rawPtr, count: count))
        }
        
        let ratio = inputRate / outputRate
        let outputCount = Int(Double(count) / ratio)
        guard outputCount > 0 else { return [] }
        
        var output = [Float](repeating: 0.0, count: outputCount)
        
        for i in 0..<outputCount {
            let srcIndex = Double(i) * ratio
            let idx0 = Int(srcIndex)
            let idx1 = min(idx0 + 1, count - 1)
            let fraction = Float(srcIndex - Double(idx0))
            
            let val0 = rawPtr[idx0]
            let val1 = rawPtr[idx1]
            output[i] = val0 + (val1 - val0) * fraction
        }
        
        return output
    }
}
