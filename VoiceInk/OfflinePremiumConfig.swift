import Foundation

struct OfflinePremiumConfig {
    static let isOfflinePremium = true
    
    // Unlock all models
    static let availableModels = PredefinedModels.models
    
    // Enhanced settings
    static let maxRecordingDuration: TimeInterval = 3600 // 1 hour
    static let enableAdvancedAI = true
    static let enableCloudSync = false // Keep offline
    static let enableCustomModels = true
    
    // Premium audio settings
    static let audioQuality: AudioQuality = .highest
    static let enableNoiseReduction = true
    static let enableEchoCancellation = true
}

enum AudioQuality {
    case standard, high, highest
    
    var sampleRate: Double {
        switch self {
        case .standard: return 16000
        case .high: return 44100
        case .highest: return 48000
        }
    }
}
