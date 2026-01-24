import Foundation
import os

/// Streaming transcription manager that processes audio in real-time
@MainActor
final class StreamingTranscriptionManager: ObservableObject {
    static let shared = StreamingTranscriptionManager()
    
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "StreamingTranscription")
    
    // Accumulated samples for transcription - pre-allocated for performance
    private var accumulatedSamples: [Float] = []
    private let sampleRate: Double = 16000
    private let maxSamples = 16000 * 60 // Max 60 seconds
    private let maxEarlySamples = 16000 * 10 // Max 10 seconds for early buffer
    private let minSamples = 2400 // Min 0.15 seconds (lowered to catch "yes", "no", etc.)
    
    // Early samples buffer (before streaming officially starts)
    private var earlySamples: [Float] = []
    private var isCollecting = false
    
    // Backpressure handling
    private var isTranscribing = false
    
    // Streaming state
    @Published var partialTranscript: String = ""
    @Published var isStreaming = false
    
    // Transcription engines
    private var streamingTask: Task<Void, Never>?
    private var whisperContext: WhisperContext?
    private var parakeetService: ParakeetTranscriptionService?
    
    private init() {
        // Pre-allocate capacity to avoid reallocations
        accumulatedSamples.reserveCapacity(maxSamples)
        earlySamples.reserveCapacity(maxEarlySamples)
    }
    
    /// Start collecting samples immediately (call when recording starts)
    func startCollecting() {
        isCollecting = true
        isTranscribing = false
        earlySamples.removeAll(keepingCapacity: true)
        accumulatedSamples.removeAll(keepingCapacity: true)
        partialTranscript = ""
        logger.notice("🎙️ Started collecting audio samples")
    }
    
    /// Start streaming with Whisper
    func startStreaming(with context: WhisperContext?) async {
        await startStreamingInternal(whisper: context, parakeet: nil)
    }
    
    /// Start streaming with Parakeet
    func startStreaming(with service: ParakeetTranscriptionService?) async {
        await startStreamingInternal(whisper: nil, parakeet: service)
    }
    
    private func startStreamingInternal(whisper: WhisperContext?, parakeet: ParakeetTranscriptionService?) async {
        guard !isStreaming else { return }
        
        // Move early samples to accumulated (preserve them!)
        let earlyCount = earlySamples.count
        if earlyCount > 0 {
            accumulatedSamples.append(contentsOf: earlySamples)
            earlySamples.removeAll(keepingCapacity: true)
            logger.notice("🎙️ Recovered \(earlyCount) early samples (\(String(format: "%.2f", Double(earlyCount)/16000.0))s)")
        }
        
        isStreaming = true
        partialTranscript = ""
        whisperContext = whisper
        parakeetService = parakeet
        
        logger.notice("🎙️ Started streaming (whisper: \(whisper != nil), parakeet: \(parakeet != nil))")
        
        // Start background transcription task
        streamingTask = Task.detached { [weak self] in
            await self?.streamingLoop()
        }
    }
    
    /// Stop streaming and get final result
    func stopStreaming() async -> String {
        isCollecting = false
        
        // Cancel and wait for streaming task
        if let task = streamingTask {
            task.cancel()
            _ = await task.result
            streamingTask = nil
        }
        
        // If streaming never started, use early samples
        if !isStreaming && !earlySamples.isEmpty {
            accumulatedSamples.append(contentsOf: earlySamples)
            earlySamples.removeAll(keepingCapacity: true)
        }
        
        isStreaming = false
        
        // Include any remaining early samples
        if !earlySamples.isEmpty {
            accumulatedSamples.insert(contentsOf: earlySamples, at: 0)
            earlySamples.removeAll(keepingCapacity: true)
        }
        
        let sampleCount = accumulatedSamples.count
        let durationSeconds = Double(sampleCount) / sampleRate
        
        // Skip if too short (0.15 seconds - allows "yes", "no", "ok")
        guard sampleCount >= minSamples else {
            logger.notice("🎙️ Recording too short (\(String(format: "%.2f", durationSeconds))s), skipping")
            accumulatedSamples.removeAll(keepingCapacity: true)
            return ""
        }
        
        // Wait for model if not ready (first recording)
        var modelReady = whisperContext != nil || (parakeetService?.isLoaded ?? false)
        if !modelReady {
            logger.notice("⏳ Waiting for model to load...")
            for _ in 0..<50 {
                if whisperContext != nil || (parakeetService?.isLoaded ?? false) {
                    modelReady = true
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        
        guard modelReady else {
            logger.error("❌ Model not loaded, cannot transcribe")
            accumulatedSamples.removeAll(keepingCapacity: true)
            return ""
        }
        
        // Apply VAD for recordings longer than 5 seconds
        var samplesToTranscribe = accumulatedSamples
        if durationSeconds >= 5.0 {
            _ = await VADManager.shared.getProvider(type: .fluidAudio)
            samplesToTranscribe = await VADManager.shared.filterSilence(from: accumulatedSamples, minDuration: 5.0)
        }
        
        logger.notice("🎙️ Transcribing \(samplesToTranscribe.count) samples (\(String(format: "%.2f", Double(samplesToTranscribe.count)/16000.0))s)")
        
        let result = await transcribeSamples(samplesToTranscribe) ?? ""
        
        // Clear sensitive audio data
        accumulatedSamples.removeAll(keepingCapacity: true)
        
        if !result.isEmpty {
            logger.notice("🎙️ Result: \(result.prefix(50))...")
        }
        
        return result
    }
    
    /// Add audio samples from recorder (called from audio callback)
    func addSamples(_ samples: [Float]) {
        guard isCollecting || isStreaming else { return }
        guard !samples.isEmpty else { return }
        
        // Direct append on MainActor (already on MainActor due to class annotation)
        if isStreaming {
            let remaining = maxSamples - accumulatedSamples.count
            if remaining > 0 {
                let toAdd = min(samples.count, remaining)
                accumulatedSamples.append(contentsOf: samples.prefix(toAdd))
            }
        } else {
            let remaining = maxEarlySamples - earlySamples.count
            if remaining > 0 {
                let toAdd = min(samples.count, remaining)
                earlySamples.append(contentsOf: samples.prefix(toAdd))
            }
        }
    }
    
    /// Stop collecting (cleanup on recording failure)
    func stopCollecting() {
        isCollecting = false
        earlySamples.removeAll(keepingCapacity: true)
        accumulatedSamples.removeAll(keepingCapacity: true)
    }
    
    /// Background streaming loop
    private func streamingLoop() async {
        // Wait for model to be ready
        var modelReady = false
        for _ in 0..<50 {
            if whisperContext != nil || (parakeetService?.isLoaded ?? false) {
                modelReady = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard modelReady else {
            logger.warning("⚠️ Model not ready for streaming")
            return
        }
        
        logger.notice("✅ Model ready for streaming")
        
        while !Task.isCancelled {
            let streaming = await MainActor.run { isStreaming }
            guard streaming else { break }
            
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            let stillStreaming = await MainActor.run { isStreaming }
            guard stillStreaming else { break }
            
            // Backpressure: skip if previous transcription still running
            let busy = await MainActor.run { isTranscribing }
            if busy { continue }
            
            // Check sample count without copying array
            let count = await MainActor.run { accumulatedSamples.count }
            guard count >= 8000 else { continue }
            
            // Only copy when we need to transcribe
            let currentSamples = await MainActor.run { Array(accumulatedSamples) }
            
            await MainActor.run { isTranscribing = true }
            if let result = await transcribeSamples(currentSamples) {
                await MainActor.run { self.partialTranscript = result }
            }
            await MainActor.run { isTranscribing = false }
        }
    }
    
    /// Transcribe samples using whisper or parakeet
    private func transcribeSamples(_ samples: [Float]) async -> String? {
        guard !samples.isEmpty else { return nil }
        
        if let parakeet = parakeetService, parakeet.isLoaded {
            return try? await parakeet.transcribeSamples(samples)
        }
        
        guard let context = whisperContext else { return nil }
        let success = await context.fullTranscribe(samples: samples)
        guard success else { return nil }
        return await context.getTranscription()
    }
}
