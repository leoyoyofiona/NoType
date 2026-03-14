import Foundation

enum CapturePhase: Equatable {
    case idle
    case preparing
    case listening
    case processing
    case failed
}

enum InputMode: CaseIterable, Equatable {
    case directChinese
    case directEnglish
    case chineseToEnglish
    case englishToChinese

    var captureEngine: CaptureEngine {
        switch self {
        case .directChinese, .directEnglish:
            return .systemDictation
        case .chineseToEnglish, .englishToChinese:
            return .customTranscription
        }
    }

    var usesSystemDictation: Bool {
        captureEngine == .systemDictation
    }

    var requiresTranslation: Bool {
        translationPair != nil
    }

    var displayName: String {
        switch self {
        case .directChinese:
            return "直接中文"
        case .directEnglish:
            return "Direct English"
        case .chineseToEnglish:
            return "中文转英文"
        case .englishToChinese:
            return "英文转中文"
        }
    }

    var shortLabel: String {
        switch self {
        case .directChinese:
            return "ZH"
        case .directEnglish:
            return "EN"
        case .chineseToEnglish:
            return "ZH→EN"
        case .englishToChinese:
            return "EN→ZH"
        }
    }

    var hotKeyHint: String {
        "Control + Option + Space"
    }

    var sourceLocale: Locale {
        switch self {
        case .directChinese, .chineseToEnglish:
            return Locale(identifier: "zh-CN")
        case .directEnglish, .englishToChinese:
            return Locale(identifier: "en-US")
        }
    }

    var outputLanguage: Locale.Language {
        switch self {
        case .directChinese, .englishToChinese:
            return Locale.Language(identifier: "zh-Hans")
        case .directEnglish, .chineseToEnglish:
            return Locale.Language(identifier: "en")
        }
    }

    var translationPair: TranslationPair? {
        switch self {
        case .englishToChinese:
            return TranslationPair(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )
        case .chineseToEnglish:
            return TranslationPair(
                source: Locale.Language(identifier: "zh-Hans"),
                target: Locale.Language(identifier: "en")
            )
        case .directChinese, .directEnglish:
            return nil
        }
    }

    var next: InputMode {
        let modes = Self.allCases
        guard let index = modes.firstIndex(of: self) else { return self }
        return modes[(index + 1) % modes.count]
    }
}

enum CaptureEngine: Equatable {
    case systemDictation
    case customTranscription
}

struct TranslationPair: Equatable {
    let source: Locale.Language
    let target: Locale.Language
}
