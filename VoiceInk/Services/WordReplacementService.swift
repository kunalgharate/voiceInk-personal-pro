import Foundation
import SwiftData

class WordReplacementService {
    static let shared = WordReplacementService()
    
    // Cache for compiled replacements
    private var cachedPatterns: [(regex: NSRegularExpression?, original: String, replacement: String, usesBoundaries: Bool)] = []
    private var cacheModelContext: ModelContext?
    private var lastCacheUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 5.0 // Refresh cache every 5 seconds max

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(invalidateCache), name: NSNotification.Name("WordReplacementsChanged"), object: nil)
    }
    
    @objc private func invalidateCache() {
        cachedPatterns = []
        lastCacheUpdate = nil
    }

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        // Check if cache needs refresh
        let needsRefresh = cachedPatterns.isEmpty || 
                          cacheModelContext !== context ||
                          (lastCacheUpdate.map { Date().timeIntervalSince($0) > cacheValidityDuration } ?? true)
        
        if needsRefresh {
            refreshCache(using: context)
        }
        
        guard !cachedPatterns.isEmpty else { return text }

        var modifiedText = text

        for pattern in cachedPatterns {
            if pattern.usesBoundaries, let regex = pattern.regex {
                let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                modifiedText = regex.stringByReplacingMatches(in: modifiedText, range: range, withTemplate: pattern.replacement)
            } else {
                modifiedText = modifiedText.replacingOccurrences(of: pattern.original, with: pattern.replacement, options: .caseInsensitive)
            }
        }

        return modifiedText
    }
    
    private func refreshCache(using context: ModelContext) {
        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let replacements = try? context.fetch(descriptor), !replacements.isEmpty else {
            cachedPatterns = []
            cacheModelContext = context
            lastCacheUpdate = Date()
            return
        }

        cachedPatterns = []
        
        for replacement in replacements {
            let variants = replacement.originalText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for original in variants {
                let usesBoundaries = usesWordBoundaries(for: original)
                var regex: NSRegularExpression? = nil
                
                if usesBoundaries {
                    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: original))\\b"
                    regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                }
                
                cachedPatterns.append((regex, original, replacement.replacementText, usesBoundaries))
            }
        }
        
        cacheModelContext = context
        lastCacheUpdate = Date()
    }

    private func usesWordBoundaries(for text: String) -> Bool {
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F, 0x30A0...0x30FF, 0x4E00...0x9FFF,
            0xAC00...0xD7AF, 0x0E00...0x0E7F
        ]

        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts {
                if range.contains(scalar.value) { return false }
            }
        }
        return true
    }
}
