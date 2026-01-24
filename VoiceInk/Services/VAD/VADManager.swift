import Foundation
import os

/// VAD Manager - Central access point for Voice Activity Detection
/// Allows switching between different VAD implementations
final class VADManager {
    static let shared = VADManager()
    
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VADManager")
    
    enum VADType: String {
        case fluidAudio = "FluidAudio"
        case silero = "Silero"
        case none = "None"
    }
    
    private var currentProvider: VADProvider?
    private var currentType: VADType = .none
    
    private init() {}
    
    /// Get or create VAD provider
    func getProvider(type: VADType = .fluidAudio, config: VADConfig = VADConfig()) -> VADProvider? {
        if currentType == type, let provider = currentProvider {
            return provider
        }
        
        switch type {
        case .fluidAudio:
            currentProvider = FluidAudioVAD(config: config)
        case .silero:
            currentProvider = SileroVAD(config: config)
        case .none:
            currentProvider = nil
        }
        
        currentType = type
        logger.notice("🎙️ VAD provider set to: \(type.rawValue)")
        return currentProvider
    }
    
    /// Filter silence from audio samples
    func filterSilence(from samples: [Float], minDuration: Double = 3.0) async -> [Float] {
        let durationSeconds = Double(samples.count) / 16000.0
        
        // Skip VAD for short recordings
        guard durationSeconds >= minDuration else {
            return samples
        }
        
        guard let provider = currentProvider else {
            return samples
        }
        
        do {
            let filtered = try await provider.filterSilence(from: samples)
            let removedSeconds = durationSeconds - Double(filtered.count) / 16000.0
            logger.notice("🎙️ VAD removed \(String(format: "%.1f", removedSeconds))s of silence")
            return filtered
        } catch {
            logger.error("🎙️ VAD failed: \(error.localizedDescription)")
            return samples
        }
    }
    
    /// Check if samples contain speech
    func containsSpeech(in samples: [Float]) async -> Bool {
        guard let provider = currentProvider else { return true }
        return await provider.containsSpeech(in: samples)
    }
}
