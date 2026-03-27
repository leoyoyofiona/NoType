import Carbon
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

enum HotKeyModifier: String, CaseIterable, Codable, Hashable, Identifiable {
    case control
    case option
    case shift
    case command

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .control:
            return "Control"
        case .option:
            return "Option"
        case .shift:
            return "Shift"
        case .command:
            return "Command"
        }
    }

    var carbonValue: UInt32 {
        switch self {
        case .control:
            return UInt32(controlKey)
        case .option:
            return UInt32(optionKey)
        case .shift:
            return UInt32(shiftKey)
        case .command:
            return UInt32(cmdKey)
        }
    }
}

enum HotKeyKey: String, CaseIterable, Codable, Hashable, Identifiable {
    case space
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z
    case zero
    case one
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .space:
            return "Space"
        case .zero:
            return "0"
        case .one:
            return "1"
        case .two:
            return "2"
        case .three:
            return "3"
        case .four:
            return "4"
        case .five:
            return "5"
        case .six:
            return "6"
        case .seven:
            return "7"
        case .eight:
            return "8"
        case .nine:
            return "9"
        case .f1:
            return "F1"
        case .f2:
            return "F2"
        case .f3:
            return "F3"
        case .f4:
            return "F4"
        case .f5:
            return "F5"
        case .f6:
            return "F6"
        case .f7:
            return "F7"
        case .f8:
            return "F8"
        case .f9:
            return "F9"
        case .f10:
            return "F10"
        case .f11:
            return "F11"
        case .f12:
            return "F12"
        default:
            return rawValue.uppercased()
        }
    }

    var carbonKeyCode: UInt32 {
        switch self {
        case .space:
            return UInt32(kVK_Space)
        case .a:
            return UInt32(kVK_ANSI_A)
        case .b:
            return UInt32(kVK_ANSI_B)
        case .c:
            return UInt32(kVK_ANSI_C)
        case .d:
            return UInt32(kVK_ANSI_D)
        case .e:
            return UInt32(kVK_ANSI_E)
        case .f:
            return UInt32(kVK_ANSI_F)
        case .g:
            return UInt32(kVK_ANSI_G)
        case .h:
            return UInt32(kVK_ANSI_H)
        case .i:
            return UInt32(kVK_ANSI_I)
        case .j:
            return UInt32(kVK_ANSI_J)
        case .k:
            return UInt32(kVK_ANSI_K)
        case .l:
            return UInt32(kVK_ANSI_L)
        case .m:
            return UInt32(kVK_ANSI_M)
        case .n:
            return UInt32(kVK_ANSI_N)
        case .o:
            return UInt32(kVK_ANSI_O)
        case .p:
            return UInt32(kVK_ANSI_P)
        case .q:
            return UInt32(kVK_ANSI_Q)
        case .r:
            return UInt32(kVK_ANSI_R)
        case .s:
            return UInt32(kVK_ANSI_S)
        case .t:
            return UInt32(kVK_ANSI_T)
        case .u:
            return UInt32(kVK_ANSI_U)
        case .v:
            return UInt32(kVK_ANSI_V)
        case .w:
            return UInt32(kVK_ANSI_W)
        case .x:
            return UInt32(kVK_ANSI_X)
        case .y:
            return UInt32(kVK_ANSI_Y)
        case .z:
            return UInt32(kVK_ANSI_Z)
        case .zero:
            return UInt32(kVK_ANSI_0)
        case .one:
            return UInt32(kVK_ANSI_1)
        case .two:
            return UInt32(kVK_ANSI_2)
        case .three:
            return UInt32(kVK_ANSI_3)
        case .four:
            return UInt32(kVK_ANSI_4)
        case .five:
            return UInt32(kVK_ANSI_5)
        case .six:
            return UInt32(kVK_ANSI_6)
        case .seven:
            return UInt32(kVK_ANSI_7)
        case .eight:
            return UInt32(kVK_ANSI_8)
        case .nine:
            return UInt32(kVK_ANSI_9)
        case .f1:
            return UInt32(kVK_F1)
        case .f2:
            return UInt32(kVK_F2)
        case .f3:
            return UInt32(kVK_F3)
        case .f4:
            return UInt32(kVK_F4)
        case .f5:
            return UInt32(kVK_F5)
        case .f6:
            return UInt32(kVK_F6)
        case .f7:
            return UInt32(kVK_F7)
        case .f8:
            return UInt32(kVK_F8)
        case .f9:
            return UInt32(kVK_F9)
        case .f10:
            return UInt32(kVK_F10)
        case .f11:
            return UInt32(kVK_F11)
        case .f12:
            return UInt32(kVK_F12)
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable {
    var key: HotKeyKey
    var modifiers: Set<HotKeyModifier>

    static let defaultValue = HotKeyConfiguration(
        key: .space,
        modifiers: [.control, .option]
    )

    var hasAnyModifier: Bool {
        !modifiers.isEmpty
    }

    var carbonModifiers: UInt32 {
        modifiers.reduce(0) { partialResult, modifier in
            partialResult | modifier.carbonValue
        }
    }

    var displayString: String {
        let orderedModifiers = HotKeyModifier.allCases
            .filter { modifiers.contains($0) }
            .map(\.displayName)
        return (orderedModifiers + [key.displayName]).joined(separator: " + ")
    }

    func contains(_ modifier: HotKeyModifier) -> Bool {
        modifiers.contains(modifier)
    }

    mutating func setModifier(_ modifier: HotKeyModifier, enabled: Bool) {
        if enabled {
            modifiers.insert(modifier)
        } else {
            modifiers.remove(modifier)
        }
    }
}
