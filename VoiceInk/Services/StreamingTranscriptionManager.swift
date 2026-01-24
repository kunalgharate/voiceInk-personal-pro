import Foundation
import os

/// Streaming transcription manager that processes audio in real-time
@MainActor
final class StreamingTranscriptionManager: ObservableObject {
    static let shared = StreamingTranscriptionManager()
    
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "StreamingTranscription")
    
    // Accumulated samples for transcription
    private var accumulatedSamples: [Float] = []
    private let sampleRate: Double = 16000
    private let maxSamples = 16000 * 60 // Max 60 seconds to prevent memory issues
    private let maxEarlySamples = 16000 * 10 // Max 10 seconds for early buffer
    
    // Early samples buffer (before streaming officially starts)
    private var earlySamples: [Float] = []
    private var isCollecting = false
    
    // Streaming state
    @Published var partialTranscript: String = ""
    @Published var isStreaming = false
    
    // Transcription engines
    private var streamingTask: Task<Void, Never>?
    private var whisperContext: WhisperContext?
    private var parakeetService: ParakeetTranscriptionService?
    
    private init() {}
    
    /// Start collecting samples immediately (call when recording starts)
    func startCollecting() {
        isCollecting = true
        earlySamples = []
        accumulatedSamples = []
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
            accumulatedSamples = earlySamples
            earlySamples = []
            logger.notice("🎙️ Recovered \(earlyCount) early samples (\(String(format: "%.2f", Double(earlyCount)/16000.0))s)")
        } else {
            accumulatedSamples = []
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
        
        // If streaming never started, use early samples
        if !isStreaming {
            if !earlySamples.isEmpty {
                accumulatedSamples = earlySamples
                earlySamples = []
            }
            if accumulatedSamples.isEmpty { return "" }
        }
        
        isStreaming = false
        streamingTask?.cancel()
        streamingTask = nil
        
        // Include any remaining early samples
        if !earlySamples.isEmpty {
            accumulatedSamples.insert(contentsOf: earlySamples, at: 0)
            earlySamples = []
        }
        
        let sampleCount = accumulatedSamples.count
        let durationSeconds = Double(sampleCount) / sampleRate
        
        // Skip if too short (less than 0.3 seconds)
        guard sampleCount >= 4800 else {
            logger.notice("🎙️ Recording too short (\(String(format: "%.1f", durationSeconds))s), skipping")
            accumulatedSamples = []
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
            accumulatedSamples = []
            return ""
        }
        
        // Apply VAD for recordings longer than 5 seconds
        var samplesToTranscribe = accumulatedSamples
        if durationSeconds >= 5.0 {
            _ = await VADManager.shared.getProvider(type: .fluidAudio)
            samplesToTranscribe = await VADManager.shared.filterSilence(from: accumulatedSamples, minDuration: 5.0)
            let filteredDuration = Double(samplesToTranscribe.count) / sampleRate
            if filteredDuration < durationSeconds {
                logger.notice("🎙️ VAD: \(String(format: "%.1f", durationSeconds))s → \(String(format: "%.1f", filteredDuration))s")
            }
        }
        
        logger.notice("🎙️ Transcribing \(samplesToTranscribe.count) samples (\(String(format: "%.1f", Double(samplesToTranscribe.count)/16000.0))s)")
        
        let result = await transcribeSamples(samplesToTranscribe) ?? ""
        accumulatedSamples = []
        
        if !result.isEmpty {
            logger.notice("🎙️ Result: \(result.prefix(50))...")
        }
        
        return result
    }
    
    /// Add audio samples from recorder (called from audio callback)
    func addSamples(_ samples: [Float]) {
        guard isCollecting || isStreaming else { return }
        
        Task { @MainActor in
            if isStreaming {
                if accumulatedSamples.count < maxSamples {
                    accumulatedSamples.append(contentsOf: samples)
                }
            } else if earlySamples.count < maxEarlySamples {
                earlySamples.append(contentsOf: samples)
            }
        }
    }
    
    /// Stop collecting (cleanup on recording failure)
    func stopCollecting() {
        isCollecting = false
        earlySamples = []
        accumulatedSamples = []
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
            
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            let stillStreaming = await MainActor.run { isStreaming }
            guard stillStreaming else { break }
            
            let currentSamples = await MainActor.run { Array(accumulatedSamples) }
            
            if currentSamples.count >= 8000 {
                if let result = await transcribeSamples(currentSamples) {
                    await MainActor.run { self.partialTranscript = result }
                }
            }
        }
    }
    
    /// Transcribe samples using whisper or parakeet
    private func transcribeSamples(_ samples: [Float]) async -> String? {
        if let parakeet = parakeetService, parakeet.isLoaded {
            return try? await parakeet.transcribeSamples(samples)
        }
        
        guard let context = whisperContext else { return nil }
        let success = await context.fullTranscribe(samples: samples)
        guard success else { return nil }
        return await context.getTranscription()
    }
}
