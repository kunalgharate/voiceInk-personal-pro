import Foundation
import os

struct TranscriptionOutputFilter {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionOutputFilter")
    
    // Pre-compiled regex patterns for performance
    private static let tagBlockRegex = try? NSRegularExpression(pattern: #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#)
    private static let bracketRegex = try? NSRegularExpression(pattern: #"\[.*?\]"#)
    private static let parenRegex = try? NSRegularExpression(pattern: #"\(.*?\)"#)
    private static let braceRegex = try? NSRegularExpression(pattern: #"\{.*?\}"#)
    private static let multiSpaceRegex = try? NSRegularExpression(pattern: #"\s{2,}"#)
    
    // Pre-compiled filler word patterns
    private static let fillerPatterns: [NSRegularExpression] = {
        let fillerWords = ["uh", "um", "uhm", "umm", "uhh", "uhhh", "ah", "eh", "hmm", "hm", "mmm", "mm", "mh", "ha", "ehh"]
        return fillerWords.compactMap { word in
            try? NSRegularExpression(pattern: "\\b\(word)\\b[,.]?", options: .caseInsensitive)
        }
    }()

    static func filter(_ text: String) -> String {
        var filteredText = text
        let fullRange = { NSRange(filteredText.startIndex..., in: filteredText) }

        // Remove <TAG>...</TAG> blocks
        if let regex = tagBlockRegex {
            filteredText = regex.stringByReplacingMatches(in: filteredText, range: fullRange(), withTemplate: "")
        }

        // Remove bracketed hallucinations
        if let regex = bracketRegex {
            filteredText = regex.stringByReplacingMatches(in: filteredText, range: fullRange(), withTemplate: "")
        }
        if let regex = parenRegex {
            filteredText = regex.stringByReplacingMatches(in: filteredText, range: fullRange(), withTemplate: "")
        }
        if let regex = braceRegex {
            filteredText = regex.stringByReplacingMatches(in: filteredText, range: fullRange(), withTemplate: "")
        }

        // Remove filler words using pre-compiled patterns
        for regex in fillerPatterns {
            filteredText = regex.stringByReplacingMatches(in: filteredText, range: fullRange(), withTemplate: "")
        }

        // Clean whitespace
        if let regex = multiSpaceRegex {
            filteredText = regex.stringByReplacingMatches(in: filteredText, range: fullRange(), withTemplate: " ")
        }
        
        return filteredText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 
