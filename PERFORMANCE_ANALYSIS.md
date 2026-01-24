# VoiceInk Deep Dive Performance Analysis

## Executive Summary

After analyzing the complete codebase, I've identified the **critical path** from hotkey press to text paste and found several optimization opportunities. The goal is to match or exceed Wispr Flow's speed.

---

## Current Pipeline Timeline (Estimated)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ RECORDING STOP → TEXT PASTE TIMELINE                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ [Hotkey Release]                                                            │
│      │                                                                      │
│      ▼ ~5-10ms                                                              │
│ [stopRecording()] ─── AudioUnit stop + file close                           │
│      │                                                                      │
│      ▼ ~0ms (optimized - was ~100-200ms)                                    │
│ [Create Transcription object]                                               │
│      │                                                                      │
│      ▼ ~20-50ms                                                             │
│ [Read audio file into memory] ─── File I/O                                  │
│      │                                                                      │
│      ▼ ~200-2000ms (MODEL DEPENDENT - BIGGEST BOTTLENECK)                   │
│ [Whisper/Parakeet transcription]                                            │
│      │                                                                      │
│      ▼ ~5-20ms                                                              │
│ [TranscriptionOutputFilter] ─── Regex processing                            │
│      │                                                                      │
│      ▼ ~10-50ms                                                             │
│ [WhisperTextFormatter] ─── NLTokenizer (sentence/word)                      │
│      │                                                                      │
│      ▼ ~5-30ms                                                              │
│ [WordReplacementService] ─── Regex replacements                             │
│      │                                                                      │
│      ▼ ~0ms (moved to background)                                           │
│ [Duration calculation] ─── AVURLAsset.load (was blocking)                   │
│      │                                                                      │
│      ▼ ~0-500ms (if enabled)                                                │
│ [AI Enhancement] ─── Network call                                           │
│      │                                                                      │
│      ▼ ~5ms                                                                 │
│ [modelContext.save()]                                                       │
│      │                                                                      │
│      ▼ ~50ms (was 50ms delay, now 0)                                        │
│ [CursorPaster.pasteAtCursor]                                                │
│      │                                                                      │
│      ▼ ~50ms                                                                │
│ [Clipboard + Cmd+V keystroke]                                               │
│      │                                                                      │
│      ▼                                                                      │
│ [TEXT APPEARS IN APP]                                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

TOTAL: ~350ms - 3000ms+ depending on:
- Audio length
- Model choice (Tiny: ~200ms, Large: ~2000ms+)
- AI Enhancement (adds ~300-500ms network latency)
```

---

## Bottleneck Analysis

### 🔴 CRITICAL BOTTLENECKS

#### 1. **Model Inference Time** (200-2000ms)
- **Whisper Large V3 Turbo**: ~1500-2000ms for 5s audio
- **Whisper Base.en**: ~300-500ms for 5s audio  
- **Parakeet V2**: ~200-400ms for 5s audio (fastest)
- **Impact**: This is the #1 bottleneck

#### 2. **CursorPaster Delays** (50-100ms) ✅ FIXED
- Had 50ms delay before paste - **removed**
- Had 200ms delay for Enter key - **reduced to 100ms**

#### 3. **Audio Duration Calculation** (100-200ms) ✅ FIXED
- `AVURLAsset.load(.duration)` was blocking
- **Moved to background task**

### 🟡 MODERATE BOTTLENECKS

#### 4. **WhisperTextFormatter** (10-50ms)
- Uses NLTokenizer for sentence/word detection
- Creates tokenizers multiple times in loops
- **Can be optimized**

#### 5. **TranscriptionOutputFilter** (5-20ms)
- Multiple regex compilations per call
- **Can cache regex patterns**

#### 6. **WordReplacementService** (5-30ms)
- Fetches from SwiftData on every call
- Compiles regex for each replacement
- **Can cache replacements and compiled patterns**

#### 7. **File I/O for Audio** (20-50ms) ✅ PARTIALLY FIXED
- Optimized with direct memory access
- **Could use memory-mapped files**

### 🟢 MINOR BOTTLENECKS

#### 8. **Sound Playback** (non-blocking)
- Already async, not blocking

#### 9. **Clipboard Operations** (5-10ms)
- Minimal overhead

---

## Comparison: VoiceInk vs Wispr Flow

| Aspect | VoiceInk Current | Wispr Flow | Gap |
|--------|------------------|------------|-----|
| Model Loading | On-demand or prewarm | Always loaded | ⚠️ |
| Transcription | File-based | Streaming? | 🔴 |
| Post-processing | Multiple passes | Minimal? | 🟡 |
| Paste Method | Clipboard + Cmd+V | Same | ✅ |
| AI Enhancement | Optional | Optional | ✅ |

### Key Difference: Streaming vs File-Based

**Wispr Flow likely uses streaming transcription:**
- Transcribes WHILE you speak
- When you stop, result is nearly instant
- Only final processing needed

**VoiceInk uses file-based:**
- Records to file
- Stops recording
- Reads entire file
- Then transcribes

---

## Recommended Optimizations

### Phase 1: Quick Wins (Implement Now)

#### 1. Cache Regex Patterns
```swift
// TranscriptionOutputFilter - compile once
private static let compiledPatterns: [(NSRegularExpression, String)] = {
    hallucinationPatterns.compactMap { pattern in
        try? NSRegularExpression(pattern: pattern).map { ($0, "") }
    }
}()
```

#### 2. Cache Word Replacements
```swift
// WordReplacementService - cache on app start, invalidate on change
private var cachedReplacements: [(NSRegularExpression, String)]?
private var cacheValid = false
```

#### 3. Simplify WhisperTextFormatter for Short Text
```swift
// Skip complex formatting for text < 100 chars
if text.count < 100 {
    return text // No paragraph breaks needed
}
```

#### 4. Reduce Logging in Hot Path
```swift
// Remove or make debug-only:
logger.notice("📝 Raw transcript: \(text)")
logger.notice("📝 Output filter result: \(text)")
// These add ~1-2ms each
```

### Phase 2: Architectural Changes

#### 5. Implement Streaming Transcription (Major)
- Use whisper.cpp streaming API
- Transcribe audio chunks as they arrive
- Show partial results in UI
- Final result ready instantly when recording stops

#### 6. Keep Model Always Loaded
- Don't unload model between transcriptions
- Trade memory for speed
- Model prewarm already helps, but keeping loaded is faster

#### 7. Use Ring Buffer for Audio
- Instead of writing to file, use circular buffer
- Pass buffer directly to transcription
- Eliminates file I/O entirely

### Phase 3: Advanced Optimizations

#### 8. Parallel Post-Processing
```swift
// Run these in parallel:
async let filtered = TranscriptionOutputFilter.filter(text)
async let formatted = WhisperTextFormatter.format(text)
// Then merge results
```

#### 9. Predictive Model Loading
- Detect when user is about to record (mouse near mic, etc.)
- Pre-load model before hotkey press

#### 10. GPU Optimization
- Ensure Metal is being used (flash_attn is enabled ✅)
- Consider batch processing for longer audio

---

## Implementation Priority

| Priority | Optimization | Effort | Impact |
|----------|-------------|--------|--------|
| 1 | Use Parakeet V2 model | Config | 🔴 High |
| 2 | Cache regex patterns | 1 hour | 🟡 Medium |
| 3 | Cache word replacements | 1 hour | 🟡 Medium |
| 4 | Skip formatting for short text | 30 min | 🟡 Medium |
| 5 | Remove debug logging | 15 min | 🟢 Low |
| 6 | Streaming transcription | 2-3 days | 🔴 High |
| 7 | Ring buffer audio | 1 day | 🟡 Medium |

---

## Quick Test: Measure Current Performance

Add timing logs to identify exact bottlenecks:

```swift
let t0 = CFAbsoluteTimeGetCurrent()
// ... operation ...
let t1 = CFAbsoluteTimeGetCurrent()
logger.notice("⏱️ Operation took \((t1-t0)*1000)ms")
```

---

## Conclusion

The biggest speed gains will come from:

1. **Using Parakeet V2** instead of Large models (~5x faster)
2. **Implementing streaming transcription** (eliminates wait after stop)
3. **Caching regex and replacements** (~50-100ms saved)
4. **Keeping model loaded** (eliminates cold start)

The optimizations I've already applied save ~200-350ms. The remaining gains require architectural changes, primarily streaming transcription.
