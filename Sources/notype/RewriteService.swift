import Foundation
@preconcurrency import FoundationModels

enum RewritePurpose {
    case directDictation
    case translatedOutput
}

@MainActor
protocol RewriteServicing {
    func rewrite(_ text: String, language: Locale.Language, purpose: RewritePurpose) async -> String
}

@MainActor
struct LocalRewriteService: RewriteServicing {
    func rewrite(_ text: String, language: Locale.Language, purpose: RewritePurpose) async -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return text }

        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default

            if case .available = model.availability, model.supportsLocale(locale(for: language)) {
                do {
                    let session = LanguageModelSession(
                        model: model,
                        instructions: instructionText(for: language, purpose: purpose)
                    )
                    let response = try await session.respond(to: normalized)
                    let rewritten = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rewritten.isEmpty {
                        DebugLogger.log("rewrite local model success purpose=\(String(describing: purpose))")
                        return rewritten
                    }
                } catch {
                    DebugLogger.log("rewrite local model failed \(error.localizedDescription)")
                }
            } else {
                DebugLogger.log("rewrite local model unavailable \(String(describing: model.availability))")
            }
        }

        let fallback = RuleBasedRewriter().rewrite(normalized, language: language, purpose: purpose)
        DebugLogger.log("rewrite rule fallback purpose=\(String(describing: purpose)) output=\(fallback)")
        return fallback
    }

    @available(macOS 26.0, *)
    private func locale(for language: Locale.Language) -> Locale {
        Locale(identifier: language.maximalIdentifier)
    }

    private func instructionText(for language: Locale.Language, purpose: RewritePurpose) -> String {
        let localeHint = language.languageCode?.identifier == "zh"
            ? "输出必须是自然、简洁、通顺的中文句子。"
            : "Output must be a natural, concise, fluent sentence in the same language."

        switch purpose {
        case .directDictation:
            return """
            Rewrite spoken dictation into a polished sentence while preserving the original meaning.
            Remove filler words, fix punctuation, and keep the output short and natural.
            Return only the rewritten text, with no explanation.
            \(localeHint)
            """
        case .translatedOutput:
            return """
            Polish translated text so it reads naturally in the target language.
            Preserve meaning, keep wording simple, and return only the final text.
            \(localeHint)
            """
        }
    }
}

private struct RuleBasedRewriter {
    func rewrite(_ text: String, language: Locale.Language, purpose: RewritePurpose) -> String {
        if language.languageCode?.identifier == "zh" {
            return rewriteChinese(text, purpose: purpose)
        }
        return rewriteEnglish(text, purpose: purpose)
    }

    private func rewriteChinese(_ text: String, purpose: RewritePurpose) -> String {
        var output = text
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[，,]{2,}", with: "，", options: .regularExpression)
            .replacingOccurrences(of: "([0-9]{1,2}):00", with: "$1点", options: .regularExpression)
            .replacingOccurrences(of: "([0-9]{1,2})点左右左右", with: "$1点左右", options: .regularExpression)

        let fillerPatterns = [
            "(^|[，。！？])那个",
            "(^|[，。！？])嗯+",
            "(^|[，。！？])呃+",
            "(^|[，。！？])啊+",
            "那个(?=(今天|明天|下午|上午|晚上|你|我|请|帮|要|去|把|在|给|3点|4点|5点|6点|7点|8点|9点))",
            "然后(?=(我|你|请|帮|要|去|把|在|给))",
            "这个(?=(是|事情|问题|方案|功能|需求))"
        ]

        for pattern in fillerPatterns {
            output = output.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
        }

        output = output
            .replacingOccurrences(of: "，+", with: "，", options: .regularExpression)
            .replacingOccurrences(of: "^，|，$", with: "", options: .regularExpression)

        if output.contains("安排"),
           (output.contains("开会") || output.contains("会议")) {
            let timePhrase = extractFirstMatch(
                in: output,
                patterns: [
                    "(今天|明天|后天)?(上午|中午|下午|晚上)?[0-9]{1,2}点(半|[0-9]{1,2}分)?左右",
                    "(今天|明天|后天)?(上午|中午|下午|晚上)?[0-9]{1,2}点(半|[0-9]{1,2}分)?",
                    "(今天|明天|后天)?(上午|中午|下午|晚上)"
                ]
            )

            if let timePhrase {
                let normalizedTime = enrichChineseTimePhrase(timePhrase, in: output)
                return "请帮我安排\(normalizedTime)开会。"
            }

            return "请帮我安排开会。"
        }

        output = output
            .replacingOccurrences(of: "安排一个会议", with: "安排开会")
            .replacingOccurrences(of: "安排一下会议", with: "安排开会")
            .replacingOccurrences(of: "安排会议那个", with: "安排开会")
            .replacingOccurrences(of: "帮我安排开会", with: "请帮我安排开会")

        if purpose == .translatedOutput {
            output = output.replacingOccurrences(of: "^请你", with: "请")
        }

        output = output.trimmingCharacters(in: CharacterSet(charactersIn: "，。！？"))
        if !output.isEmpty, !"。！？".contains(output.last ?? " ") {
            output.append("。")
        }

        return output
    }

    private func enrichChineseTimePhrase(_ timePhrase: String, in fullText: String) -> String {
        var enriched = timePhrase

        if !enriched.contains("今天"), fullText.contains("今天") {
            enriched = "今天" + enriched
        } else if !enriched.contains("明天"), fullText.contains("明天") {
            enriched = "明天" + enriched
        } else if !enriched.contains("后天"), fullText.contains("后天") {
            enriched = "后天" + enriched
        }

        if !enriched.contains("上午"), fullText.contains("上午") {
            enriched = enriched.replacingOccurrences(of: "今天", with: "今天上午")
            if !enriched.contains("上午") {
                enriched = "上午" + enriched
            }
        } else if !enriched.contains("中午"), fullText.contains("中午") {
            enriched = enriched.replacingOccurrences(of: "今天", with: "今天中午")
            if !enriched.contains("中午") {
                enriched = "中午" + enriched
            }
        } else if !enriched.contains("下午"), fullText.contains("下午") {
            enriched = enriched.replacingOccurrences(of: "今天", with: "今天下午")
            if !enriched.contains("下午") {
                enriched = "下午" + enriched
            }
        } else if !enriched.contains("晚上"), fullText.contains("晚上") {
            enriched = enriched.replacingOccurrences(of: "今天", with: "今天晚上")
            if !enriched.contains("晚上") {
                enriched = "晚上" + enriched
            }
        }

        return enriched
    }

    private func rewriteEnglish(_ text: String, purpose: RewritePurpose) -> String {
        var output = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\b(uh|um|you know|like)\\b", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+([,.;!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if output.localizedCaseInsensitiveContains("schedule"),
           output.localizedCaseInsensitiveContains("meeting") {
            if let timePhrase = extractFirstMatch(
                in: output,
                patterns: [
                    "(this|tomorrow|next)?\\s*(morning|afternoon|evening)?\\s*[0-9]{1,2}(:[0-9]{2})?\\s*(am|pm)?",
                    "(this|tomorrow|next)?\\s*(morning|afternoon|evening)"
                ]
            ) {
                output = "Please schedule a meeting around \(timePhrase.trimmingCharacters(in: .whitespaces))."
            }
        }

        if let first = output.first {
            output.replaceSubrange(output.startIndex...output.startIndex, with: String(first).uppercased())
        }

        if !output.isEmpty, !".!?".contains(output.last ?? " ") {
            output.append(".")
        }

        return output
    }

    private func extractFirstMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                return String(text[range])
            }
        }
        return nil
    }
}
