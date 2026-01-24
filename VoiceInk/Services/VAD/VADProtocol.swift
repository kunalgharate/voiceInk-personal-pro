import Foundation

/// Protocol for Voice Activity Detection implementations
/// Allows swapping between different VAD engines (FluidAudio, Silero, WebRTC, etc.)
protocol VADProvider {
    /// Filter audio samples to remove silence
    /// - Parameter samples: Raw audio samples at 16kHz
    /// - Returns: Filtered samples with silence removed
    func filterSilence(from samples: [Float]) async throws -> [Float]
    
    /// Check if a segment contains speech
    /// - Parameter samples: Audio samples to check
    /// - Returns: True if speech detected
    func containsSpeech(in samples: [Float]) async -> Bool
    
    /// Get speech segments from audio
    /// - Parameter samples: Raw audio samples
    /// - Returns: Array of sample ranges containing speech
    func getSpeechSegments(from samples: [Float]) async throws -> [(start: Int, end: Int)]
}

/// VAD configuration
struct VADConfig {
    /// Threshold for speech detection (0.0 - 1.0)
    var threshold: Float = 0.5
    
    /// Minimum speech duration in seconds
    var minSpeechDuration: Float = 0.1
    
    /// Minimum silence duration to split segments
    var minSilenceDuration: Float = 0.3
    
    /// Sample rate (default 16kHz for Whisper)
    var sampleRate: Int = 16000
}
