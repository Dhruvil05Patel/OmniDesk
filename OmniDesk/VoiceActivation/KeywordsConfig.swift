//
//  KeywordsConfig.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 01/11/26.
//

import Foundation

/// Sensitivity levels for wake-word detection.
public enum WakeWordSensitivity: String, CaseIterable, Codable, Sendable {
    case low = "Low"
    case balanced = "Balanced"
    case high = "High"
    
    /// The detection threshold multiplier applied to keyword posterior scores.
    public var thresholdModifier: Float {
        switch self {
        case .low: return 0.50
        case .balanced: return 0.35
        case .high: return 0.22
        }
    }
}

/// Represents a keyword spotting entry with phonetic tokens, boost weight, and detection threshold.
public struct KeywordEntry: Codable, Sendable, Equatable {
    public let phrase: String
    public let boostWeight: Float
    public let baseThreshold: Float
    public let phoneticTokens: [String]
    
    public init(phrase: String, boostWeight: Float, baseThreshold: Float, phoneticTokens: [String] = []) {
        self.phrase = phrase.uppercased()
        self.boostWeight = boostWeight
        self.baseThreshold = baseThreshold
        self.phoneticTokens = phoneticTokens.isEmpty ? phrase.uppercased().components(separatedBy: " ") : phoneticTokens
    }
}

/// Configuration manager for customizable wake-word spotting in OmniDesk.
public struct KeywordsConfig: Codable, Sendable, Equatable {
    
    public var activeKeyword: String
    public var sensitivity: WakeWordSensitivity
    public var keywords: [KeywordEntry]
    public var falsePositiveBlocklist: [String]
    
    /// Default configuration for the custom wake word "Dhuli" (pronounced "dh-u-li").
    public static let `default` = KeywordsConfig(
        activeKeyword: "DHULI",
        sensitivity: .balanced,
        keywords: [
            KeywordEntry(
                phrase: "DHULI",
                boostWeight: 1.5,
                baseThreshold: 0.35,
                phoneticTokens: ["DH", "UW", "L", "IY"]
            ),
            KeywordEntry(
                phrase: "DHOOLI",
                boostWeight: 1.4,
                baseThreshold: 0.38,
                phoneticTokens: ["DH", "UW", "L", "IY"]
            ),
            KeywordEntry(
                phrase: "HEY DHULI",
                boostWeight: 1.8,
                baseThreshold: 0.40,
                phoneticTokens: ["HH", "EY", "DH", "UW", "L", "IY"]
            ),
            KeywordEntry(
                phrase: "DOOLI",
                boostWeight: 1.2,
                baseThreshold: 0.42,
                phoneticTokens: ["D", "UW", "L", "IY"]
            )
        ],
        falsePositiveBlocklist: [
            "JULIE", "DAILY", "DO IT", "TRULY", "DUTY", "DOOLEY", "COOLIE", "DEWEY"
        ]
    )
    
    public init(
        activeKeyword: String = "DHULI",
        sensitivity: WakeWordSensitivity = .balanced,
        keywords: [KeywordEntry] = [],
        falsePositiveBlocklist: [String] = []
    ) {
        self.activeKeyword = activeKeyword.uppercased()
        self.sensitivity = sensitivity
        self.keywords = keywords.isEmpty ? Self.default.keywords : keywords
        self.falsePositiveBlocklist = falsePositiveBlocklist.isEmpty ? Self.default.falsePositiveBlocklist : falsePositiveBlocklist
    }
    
    /// Effective threshold computed for the primary active keyword under current sensitivity.
    public var effectiveThreshold: Float {
        if let primary = keywords.first(where: { $0.phrase == activeKeyword }) {
            return primary.baseThreshold * (sensitivity.thresholdModifier / 0.35)
        }
        return sensitivity.thresholdModifier
    }
    
    /// Mutates the active sensitivity setting.
    public mutating func setSensitivity(_ newSensitivity: WakeWordSensitivity) {
        self.sensitivity = newSensitivity
    }
    
    /// Mutates the active keyword phrase to spot (e.g. "DHULI" or "HEY DHULI").
    public mutating func setActiveKeyword(_ phrase: String) {
        self.activeKeyword = phrase.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    
    /// Validates whether a candidate phoneme / text token matches the wake word or is a blocked phonetic impostor.
    public func evaluateTokenCandidate(_ candidate: String, score: Float) -> (isMatch: Bool, matchedPhrase: String?, confidence: Float) {
        let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Immediate rejection if in false positive blocklist
        for blocked in falsePositiveBlocklist {
            if normalized == blocked || normalized.contains(blocked) {
                return (false, nil, 0.0)
            }
        }
        
        // 1. Check exact matches first
        for entry in keywords {
            if normalized == entry.phrase {
                let boostedScore = score * entry.boostWeight
                let requiredThreshold = entry.baseThreshold * (sensitivity.thresholdModifier / 0.35)
                if boostedScore >= requiredThreshold {
                    return (true, entry.phrase, boostedScore)
                }
            }
        }
        
        // 2. Check contains matches sorted by descending phrase length
        let sortedKeywords = keywords.sorted(by: { $0.phrase.count > $1.phrase.count })
        for entry in sortedKeywords {
            if normalized.contains(entry.phrase) {
                let boostedScore = score * entry.boostWeight
                let requiredThreshold = entry.baseThreshold * (sensitivity.thresholdModifier / 0.35)
                if boostedScore >= requiredThreshold {
                    return (true, entry.phrase, boostedScore)
                }
            }
        }
        
        return (false, nil, score)
    }
}
