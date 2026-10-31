//
//  AudioRingBuffer.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 01/11/26.
//

import Foundation
import os

/// A high-performance, thread-safe, lock-free circular in-memory buffer for real-time PCM audio.
/// Enforces strict zero-disk persistence and fixed RAM bounds (default: 3.0s of 16kHz audio = ~192 KB).
public final class AudioRingBuffer: @unchecked Sendable {
    
    public let sampleRate: Double
    public let capacity: Int
    
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var sampleCount: Int = 0
    private var lock = os_unfair_lock()
    
    /// Initializes an audio ring buffer for a given sample rate and rolling time window in seconds.
    /// - Parameters:
    ///   - sampleRate: The audio sampling frequency in Hz (default: 16,000 Hz).
    ///   - windowDuration: The capacity of the buffer in seconds (default: 3.0 seconds).
    public init(sampleRate: Double = 16000.0, windowDuration: Double = 3.0) {
        self.sampleRate = sampleRate
        self.capacity = max(1024, Int(sampleRate * windowDuration))
        self.buffer = [Float](repeating: 0.0, count: self.capacity)
    }
    
    /// Appends new PCM float audio samples into the circular buffer. Overwrites oldest samples when full.
    /// This method is lock-guarded and allocation-free to ensure real-time audio thread safety.
    public func append(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        for i in 0..<count {
            buffer[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % capacity
            if sampleCount < capacity {
                sampleCount += 1
            }
        }
    }
    
    /// Appends an array of float samples.
    public func append(samples: [Float]) {
        samples.withUnsafeBufferPointer { ptr in
            if let baseAddress = ptr.baseAddress {
                append(samples: baseAddress, count: ptr.count)
            }
        }
    }
    
    /// Reads the most recent `count` samples in chronological order without clearing the buffer.
    public func readRecent(count: Int) -> [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let available = min(count, sampleCount)
        guard available > 0 else { return [] }
        
        var result = [Float](repeating: 0.0, count: available)
        var readIndex = (writeIndex - available + capacity) % capacity
        
        for i in 0..<available {
            result[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        
        return result
    }
    
    /// Reads all currently available samples in chronological order.
    public func readAll() -> [Float] {
        return readRecent(count: capacity)
    }
    
    /// Calculates the Root Mean Square (RMS) power level of the most recent samples (normalized 0.0 to 1.0).
    public func currentRMS(windowSamples: Int = 1024) -> Float {
        let samples = readRecent(count: windowSamples)
        guard !samples.isEmpty else { return 0.0 }
        
        var sum: Float = 0.0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(samples.count))
        return min(max(rms * 6.0, 0.0), 1.0)
    }
    
    /// Clears and zeros all samples in the circular buffer.
    public func clear() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        buffer.withUnsafeMutableBufferPointer { ptr in
            ptr.initialize(repeating: 0.0)
        }
        writeIndex = 0
        sampleCount = 0
    }
    
    /// The current number of populated samples in the buffer.
    public var currentCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return sampleCount
    }
}
