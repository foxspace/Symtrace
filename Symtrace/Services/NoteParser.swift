// Symtrace — Co-created by Mason × AI.

import Foundation
import UIKit

/// On-device parser that extracts structured suggestions from a free-form
/// note. No LLM, no network, no bundled model — pure Swift + Apple's built-in
/// `UITextChecker` for spelling correction.
///
/// Three layers of resilience to user input:
/// 1. **Direct match** against the user's own symptom/trigger names.
/// 2. **Fuzzy match** (bounded Levenshtein distance) for typos like
///    "headack" → "headache".
/// 3. **Alias dictionary** for common medical synonyms — "migraine" maps to
///    "headache" if the user has a Headache symptom; "queasy" maps to
///    "nausea"; etc. We then run the fuzzy matcher on the canonical term
///    against the user's actual list, so the alias only fires when it
///    actually corresponds to something the user is tracking.
///
/// Severity, sleep, and day-rating extraction use simple keyword + regex
/// matching. Anything ambiguous is intentionally skipped — the parser
/// suggests *only what it's confident about* and the user always reviews
/// before any write happens.
struct NoteParser {

    // MARK: - Public API

    /// Parse `note` and produce suggestions for the user to review.
    /// Returned suggestions only include items that would actually change
    /// the current entry (no-ops are filtered).
    func parse(
        note rawNote: String,
        symptoms: [SymptomDefinition],
        triggers: [TriggerDefinition],
        currentEntry: DailyEntry?
    ) -> [ParsedSuggestion] {
        let note = rawNote.lowercased()
        guard !note.isEmpty else { return [] }

        let tokens = tokenize(note)
        var suggestions: [ParsedSuggestion] = []

        for symptom in symptoms {
            if let suggested = matchSymptom(symptom, in: tokens, fullNote: note) {
                let current = currentSeverity(for: symptom, in: currentEntry)
                suggestions.append(.symptom(symptom, current: current, suggested: suggested))
            }
        }

        for trigger in triggers {
            if let suggested = matchTrigger(trigger, in: tokens, fullNote: note) {
                let current = currentValue(for: trigger, in: currentEntry)
                suggestions.append(.trigger(trigger, current: current, suggested: suggested))
            }
        }

        if let suggested = extractSleep(from: note) {
            suggestions.append(.sleep(current: currentEntry?.sleepHours, suggested: suggested))
        }

        if let suggested = extractDayRating(from: tokens, fullNote: note) {
            suggestions.append(.dayRating(current: currentEntry?.dayRating, suggested: suggested))
        }

        return suggestions.filter { $0.changesValue }
    }

    // MARK: - Tokenization

    /// Split note into lowercase tokens. Strips punctuation but keeps numerics
    /// (we need them for severity and sleep hours).
    private func tokenize(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Symptom / trigger matching

    /// Find a severity (1–4) for `symptom` in the tokens, or nil if the
    /// symptom isn't mentioned, or is mentioned without a determinable severity.
    private func matchSymptom(
        _ symptom: SymptomDefinition,
        in tokens: [String],
        fullNote: String
    ) -> Int? {
        guard let matchIndex = findMentionIndex(of: symptom.name, in: tokens) else {
            return nil
        }
        return findIntegerSeverity(near: matchIndex, in: tokens)
            ?? findDescriptiveSeverity(near: matchIndex, in: tokens)
    }

    /// Find a 0–10 value for `trigger` in the tokens, or nil if not mentioned
    /// or no determinable value.
    private func matchTrigger(
        _ trigger: TriggerDefinition,
        in tokens: [String],
        fullNote: String
    ) -> Double? {
        guard let matchIndex = findMentionIndex(of: trigger.name, in: tokens) else {
            return nil
        }
        // Triggers use 0–10, so accept any small integer near the mention.
        if let intValue = findIntegerNear(matchIndex, in: tokens, maxValue: 10) {
            return Double(intValue)
        }
        // Fall back to severity-word mapping scaled to 0–10.
        if let severity = findDescriptiveSeverity(near: matchIndex, in: tokens) {
            // 1→2, 2→5, 3→7, 4→9 — rough but matches user intent.
            switch severity {
            case 1: return 2
            case 2: return 5
            case 3: return 7
            case 4: return 9
            default: return nil
            }
        }
        return nil
    }

    /// Locate where in `tokens` the given name (or its alias / fuzzy variant)
    /// is mentioned. Returns the token index.
    private func findMentionIndex(of name: String, in tokens: [String]) -> Int? {
        let target = name.lowercased()

        // Fast path: substring of full token (handles multi-word names too).
        for (i, token) in tokens.enumerated() {
            if token == target || token.contains(target) || target.contains(token) {
                return i
            }
        }

        // Fuzzy match: each token within bounded edit distance of the name.
        for (i, token) in tokens.enumerated() {
            if isFuzzyMatch(token, target) { return i }
        }

        // Alias match: any alias word for the canonical category that matches `target`.
        if let canonical = canonicalCategory(for: target) {
            for (i, token) in tokens.enumerated() {
                if Self.aliases[canonical]?.contains(token) == true { return i }
                if isFuzzyMatch(token, canonical) { return i }
            }
        }

        // UITextChecker fallback: spell-correct each unmatched token, retry.
        for (i, token) in tokens.enumerated() where token.count >= 4 {
            for correction in spellCorrections(for: token) {
                if correction == target || isFuzzyMatch(correction, target) {
                    return i
                }
                if let canonical = canonicalCategory(for: target),
                   Self.aliases[canonical]?.contains(correction) == true {
                    return i
                }
            }
        }

        return nil
    }

    // MARK: - Severity extraction

    /// Look for a digit 0–4 within ±3 tokens of the mention index.
    private func findIntegerSeverity(near index: Int, in tokens: [String]) -> Int? {
        findIntegerNear(index, in: tokens, maxValue: 4)
    }

    /// Look for any integer up to `maxValue` within ±3 tokens of `index`.
    private func findIntegerNear(_ index: Int, in tokens: [String], maxValue: Int) -> Int? {
        let lower = max(0, index - 3)
        let upper = min(tokens.count - 1, index + 3)
        for i in lower...upper where i != index {
            // Strip "/4" or "/10" style suffixes.
            let cleaned = tokens[i].split(separator: "/").first.map(String.init) ?? tokens[i]
            if let value = Int(cleaned), value >= 0, value <= maxValue {
                return value
            }
        }
        return nil
    }

    /// Map descriptive severity words (mild / moderate / bad / severe / etc.)
    /// to a 1–4 scale. Honors leading intensifiers ("very", "really",
    /// "extremely") by bumping the result up by one (capped at 4).
    private func findDescriptiveSeverity(near index: Int, in tokens: [String]) -> Int? {
        let lower = max(0, index - 3)
        let upper = min(tokens.count - 1, index + 3)
        for i in lower...upper where i != index {
            if let base = Self.severityWords[tokens[i]] {
                let intensified: Bool = {
                    guard i > 0 else { return false }
                    return Self.intensifiers.contains(tokens[i - 1])
                }()
                return min(4, base + (intensified ? 1 : 0))
            }
        }
        return nil
    }

    // MARK: - Sleep extraction

    /// Pull a sleep duration from the note, if any.
    /// Matches "8h", "8 hours", "slept 8", "8.5 hr", etc.
    private func extractSleep(from note: String) -> Double? {
        let patterns = [
            // "slept 8", "slept 8h", "slept 8.5 hours"
            #"slept\s+(\d+(?:\.\d+)?)"#,
            // "8h sleep", "8.5 hours sleep", "5hr"
            #"(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours)\s*(?:of\s+)?(?:sleep)?"#
        ]
        for pattern in patterns {
            if let match = firstRegexCapture(pattern: pattern, in: note),
               let value = Double(match), value >= 0, value <= 14 {
                return value
            }
        }
        return nil
    }

    /// Returns the first capture group of `pattern` in `text`, or nil.
    private func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    // MARK: - Day rating extraction

    private func extractDayRating(from tokens: [String], fullNote: String) -> DayRating? {
        // Look for explicit day-rating phrases first.
        if fullNote.contains("feeling fine") || fullNote.contains("feeling great")
            || fullNote.contains("good day") || fullNote.contains("great day") {
            return .good
        }
        if fullNote.contains("bad day") || fullNote.contains("rough day")
            || fullNote.contains("terrible day") || fullNote.contains("awful day") {
            return .bad
        }
        if fullNote.contains("ok day") || fullNote.contains("okay day")
            || fullNote.contains("alright") {
            return .ok
        }
        return nil
    }

    // MARK: - Fuzzy matching (Levenshtein)

    /// Returns true if `a` and `b` are within a tolerance based on length.
    /// Short words (≤4) need exact match; longer words tolerate 1–2 edits.
    private func isFuzzyMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let lenA = a.count, lenB = b.count
        let maxLen = max(lenA, lenB)
        let tolerance: Int
        switch maxLen {
        case 0...3: tolerance = 0
        case 4...5: tolerance = 1
        default: tolerance = 2
        }
        if abs(lenA - lenB) > tolerance { return false }
        return levenshtein(a, b) <= tolerance
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let aLen = aChars.count, bLen = bChars.count
        if aLen == 0 { return bLen }
        if bLen == 0 { return aLen }

        var prev = Array(0...bLen)
        var curr = Array(repeating: 0, count: bLen + 1)
        for i in 1...aLen {
            curr[0] = i
            for j in 1...bLen {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = Swift.min(
                    Swift.min(curr[j - 1] + 1, prev[j] + 1),
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[bLen]
    }

    // MARK: - Spell correction

    /// Use Apple's built-in `UITextChecker` to suggest corrections for `word`.
    /// Returns up to 3 lowercase suggestions.
    private func spellCorrections(for word: String) -> [String] {
        let checker = UITextChecker()
        let nsWord = word as NSString
        let range = NSRange(location: 0, length: nsWord.length)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: "en"
        )
        // Not misspelled → no corrections needed.
        guard misspelled.location != NSNotFound else { return [] }
        let guesses = checker.guesses(forWordRange: misspelled, in: word, language: "en") ?? []
        return guesses.prefix(3).map { $0.lowercased() }
    }

    // MARK: - Aliases

    /// If `term` is itself a canonical category (or matches one fuzzily),
    /// return the canonical name; otherwise nil.
    private func canonicalCategory(for term: String) -> String? {
        let lowered = term.lowercased()
        if Self.aliases.keys.contains(lowered) { return lowered }
        for canonical in Self.aliases.keys where isFuzzyMatch(lowered, canonical) {
            return canonical
        }
        return nil
    }

    /// Common medical synonyms. Keys are canonical category names; values are
    /// alias words a user might write in a note. The match path is:
    ///   1. user has a symptom whose name fuzzy-matches a canonical category;
    ///   2. note contains an alias word for that canonical category;
    ///   3. → match.
    /// Intentionally small and conservative — wrong matches are worse than misses.
    private static let aliases: [String: Set<String>] = [
        "headache": ["migraine", "migraines", "head", "headaches"],
        "fatigue": ["tired", "exhausted", "wiped", "drained", "tiredness", "exhaustion"],
        "anxiety": ["anxious", "nervous", "panic", "panicky", "worried"],
        "nausea": ["nauseous", "queasy", "sick", "stomachsick"],
        "pain": ["ache", "aches", "sore", "soreness", "hurt", "hurting"],
        "insomnia": ["sleepless", "sleeplessness"],
        "dizziness": ["dizzy", "vertigo", "lightheaded", "lightheadedness"],
        "stomachache": ["tummy", "tummyache", "bellyache", "stomach"],
        "brain fog": ["foggy", "fog", "brainfog", "fuzzy"]
    ]

    /// Severity descriptors → 1–4 mapping. Intensifiers below add +1 (max 4).
    private static let severityWords: [String: Int] = [
        "mild": 1, "slight": 1, "minor": 1, "small": 1, "little": 1,
        "moderate": 2, "medium": 2, "okay": 2, "ok": 2, "some": 2,
        "bad": 3, "severe": 3, "strong": 3, "rough": 3, "intense": 3, "harsh": 3,
        "terrible": 4, "awful": 4, "worst": 4, "horrible": 4, "unbearable": 4
    ]

    private static let intensifiers: Set<String> = [
        "very", "really", "extremely", "super", "incredibly", "so"
    ]

    // MARK: - Current value lookup

    private func currentSeverity(for symptom: SymptomDefinition, in entry: DailyEntry?) -> Int {
        let id = symptom.id
        return entry?.symptomLogs?
            .first(where: { $0.symptom?.id == id })?
            .severity ?? 0
    }

    private func currentValue(for trigger: TriggerDefinition, in entry: DailyEntry?) -> Double {
        let id = trigger.id
        return entry?.triggerValues?
            .first(where: { $0.trigger?.id == id })?
            .value ?? 0
    }
}
