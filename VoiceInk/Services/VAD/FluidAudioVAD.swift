import Foundation
import FluidAudio
import os

/// VAD implementation using FluidAudio's VadManager (current VoiceInk VAD)
final class FluidAudioVAD: VADProvider {
    private var vadManager: VadManager?
    private let config: VADConfig
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioVAD")
    
    init(config: VADConfig = VADConfig()) {
        self.config = config
    }
    
    private func ensureInitialized() async throws {
        guard vadManager == nil else { return }
        let vadConfig = VadConfig(defaultThreshold: config.threshold)
        vadManager = try await VadManager(config: vadConfig)
    }
    
    func filterSilence(from samples: [Float]) async throws -> [Float] {
        try await ensureInitialized()
        guard let vad = vadManager else { return samples }
        
        let segments = try await vad.segmentSpeechAudio(samples)
        return segments.isEmpty ? samples : segments.flatMap { $0 }
    }
    
    func containsSpeech(in samples: [Float]) async -> Bool {
        do {
            try await ensureInitialized()
            guard let vad = vadManager else { return true }
            let segments = try await vad.segmentSpeechAudio(samples)
            return !segments.isEmpty
        } catch {
            return true // Assume speech on error
        }
    }
    
    func getSpeechSegments(from samples: [Float]) async throws -> [(start: Int, end: Int)] {
        try await ensureInitialized()
        guard let vad = vadManager else { return [(0, samples.count)] }
        
        // FluidAudio returns actual samples, not ranges
        // For now, return full range if speech detected
        let segments = try await vad.segmentSpeechAudio(samples)
        if segments.isEmpty {
            return []
        }
        return [(0, samples.count)]
    }
}
