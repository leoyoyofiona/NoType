import Foundation
@preconcurrency import Translation

@MainActor
protocol TranslationServicing {
    func configure(for mode: InputMode)
    func translate(_ text: String, mode: InputMode) async -> String
}

@MainActor
struct TextPipeline {
    let translationService: TranslationServicing
    let rewriteService: RewriteServicing
    let polisher: SentencePolisher

    func renderPreview(_ text: String, mode: InputMode) async -> String {
        let translated = await translationService.translate(text, mode: mode)
        return polisher.polishPreview(translated, language: mode.outputLanguage)
    }

    func finalize(_ text: String, mode: InputMode) async -> String {
        let translated = await translationService.translate(text, mode: mode)
        let rewritten = await rewriteService.rewrite(
            translated,
            language: mode.outputLanguage,
            purpose: mode.requiresTranslation ? .translatedOutput : .directDictation
        )
        return polisher.polishFinal(rewritten, language: mode.outputLanguage)
    }

    func finalizeDirect(_ text: String, language: Locale.Language) async -> String {
        let rewritten = await rewriteService.rewrite(
            text,
            language: language,
            purpose: .directDictation
        )
        return polisher.polishFinal(rewritten, language: language)
    }
}

struct SentencePolisher {
    func polishPreview(_ text: String, language: Locale.Language) -> String {
        polish(text, language: language, strict: false)
    }

    func polishFinal(_ text: String, language: Locale.Language) -> String {
        polish(text, language: language, strict: true)
    }

    private func polish(_ text: String, language: Locale.Language, strict: Bool) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        output = output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if language.languageCode?.identifier == "zh" {
            output = output
                .replacingOccurrences(of: " ,", with: "，")
                .replacingOccurrences(of: ",", with: "，")
                .replacingOccurrences(of: " .", with: "。")
                .replacingOccurrences(of: ".", with: strict ? "。" : ".")
                .replacingOccurrences(of: " ?", with: "？")
                .replacingOccurrences(of: "!", with: "！")
                .replacingOccurrences(of: " ", with: "")
        } else {
            output = output
                .replacingOccurrences(of: "\\s+([,.;!?])", with: "$1", options: .regularExpression)
                .replacingOccurrences(of: "([,.;!?])([A-Za-z])", with: "$1 $2", options: .regularExpression)

            if strict, let first = output.first {
                output.replaceSubrange(output.startIndex...output.startIndex, with: String(first).uppercased())
                if !".!?".contains(output.last ?? " ") {
                    output.append(".")
                }
            }
        }

        return output
    }
}

@MainActor
final class TranslationController: ObservableObject {
    @Published private(set) var configuration: TranslationSession.Configuration?

    private var session: TranslationSession?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func configure(for mode: InputMode) {
        guard let pair = mode.translationPair else {
            configuration = nil
            session = nil
            resumeWaiters()
            DebugLogger.log("translation configure disabled mode=\(mode.shortLabel)")
            return
        }

        let newConfiguration = TranslationSession.Configuration(
            source: pair.source,
            target: pair.target
        )

        if configuration == newConfiguration, session != nil {
            return
        }

        configuration = newConfiguration
        session = nil
        DebugLogger.log("translation configure source=\(pair.source.maximalIdentifier) target=\(pair.target.maximalIdentifier)")
    }

    func bind(_ session: TranslationSession) async {
        self.session = session
        do {
            try await session.prepareTranslation()
            DebugLogger.log("translation session prepared")
        } catch {
            // Language packs may need to be downloaded manually in system UI.
            DebugLogger.log("translation prepare failed \(error.localizedDescription)")
        }
        resumeWaiters()
    }

    func translate(_ text: String, mode: InputMode) async -> String {
        guard mode.translationPair != nil else { return text }

        await waitForSession()

        guard let session else {
            DebugLogger.log("translation session unavailable mode=\(mode.shortLabel)")
            return text
        }

        do {
            let response = try await session.translate(text)
            DebugLogger.log("translation success source=\(text) target=\(response.targetText)")
            return response.targetText
        } catch {
            DebugLogger.log("translation failed \(error.localizedDescription)")
            return text
        }
    }

    private func waitForSession() async {
        guard session == nil else { return }

        for _ in 0..<40 {
            if session != nil {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func resumeWaiters() {
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
struct SystemTranslationService: TranslationServicing {
    let controller: TranslationController

    func configure(for mode: InputMode) {
        Task { @MainActor in
            controller.configure(for: mode)
        }
    }

    func translate(_ text: String, mode: InputMode) async -> String {
        await controller.translate(text, mode: mode)
    }
}
