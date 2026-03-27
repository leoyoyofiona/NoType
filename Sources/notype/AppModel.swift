import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private static let hotKeyDefaultsKey = "NoTypeHotKeyConfiguration"

    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var mode: InputMode = .directChinese
    @Published private(set) var previewText = "准备就绪"
    @Published private(set) var committedText = ""
    @Published private(set) var lastError = ""
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var microphoneGranted = false
    @Published private(set) var speechGranted = false
    @Published private(set) var hotKeyConfiguration = HotKeyConfiguration.defaultValue

    let translationController = TranslationController()

    private let permissions = PermissionCoordinator()
    private let speechRecognizer = SpeechRecognizerService()
    private let hotKeys = GlobalHotKeyManager()
    private let injector = GlobalTextInjector()
    private let systemDictation = SystemDictationController()
    private let frontmostInspector = FrontmostAppInspector()
    private var injectionSession: TextInjectionSession?
    private var directSession: DirectDictationSession?
    private var directFallbackBaseline = ""
    private var directFallbackIdleSince: Date?
    private var directMonitorTask: Task<Void, Never>?
    private var directFinalizeTask: Task<Void, Never>?
    private var activeCaptureEngine: CaptureEngine?
    private var shouldAdvanceModeAfterCurrentCapture = false

    private lazy var pipeline = TextPipeline(
        translationService: SystemTranslationService(controller: translationController),
        rewriteService: LocalRewriteService(),
        polisher: SentencePolisher()
    )

    init() {
        DebugLogger.reset()
        DebugLogger.log("AppModel init")
        hotKeyConfiguration = Self.loadHotKeyConfiguration()
        refreshPermissions()
        installHotKeys()
        prewarmSpeechAssets()
    }

    var phaseTitle: String {
        switch phase {
        case .idle:
            return "待命"
        case .preparing:
            return "准备中"
        case .listening:
            return "正在听写"
        case .processing:
            return "正在整理"
        case .failed:
            return "发生错误"
        }
    }

    var statusSummary: String {
        "\(phaseTitle) · \(mode.shortLabel)"
    }

    var hotKeyDisplayString: String {
        hotKeyConfiguration.displayString
    }

    var menuHint: String {
        switch phase {
        case .idle:
            if mode.usesSystemDictation {
                return "按 \(hotKeyConfiguration.displayString) 触发系统听写；结束后会自动整理语句。"
            }
            return "按 \(hotKeyConfiguration.displayString) 开始翻译听写。"
        case .preparing:
            return "正在准备翻译听写资源，首次启动可能需要几秒。"
        case .listening:
            if mode.usesSystemDictation {
                return "系统听写正在工作，结束后应触发整理与替换。"
            }
            return "再次按热键即可立即提交，也会在静音后自动结束。"
        case .processing:
            return "正在整理文本并准备回填。"
        case .failed:
            return lastError
        }
    }

    func refreshPermissions() {
        accessibilityGranted = permissions.hasAccessibilityAccess
        microphoneGranted = permissions.hasMicrophoneAccess
        speechGranted = permissions.hasSpeechAccess
        DebugLogger.log("permissions accessibility=\(accessibilityGranted) microphone=\(microphoneGranted) speech=\(speechGranted)")
    }

    func requestAccessibilityAccess() {
        DebugLogger.log("request accessibility access")
        permissions.promptForAccessibilityAccess()
        refreshPermissions()
        Task { @MainActor [weak self] in
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(250))
                self?.refreshPermissions()
                if self?.accessibilityGranted == true {
                    break
                }
            }
        }
    }

    func cycleMode() {
        mode = mode.next
        translationController.configure(for: mode)
        DebugLogger.log("cycle mode -> \(mode.shortLabel)")

        if phase == .idle {
            previewText = "\(mode.displayName) 已启用"
        }
    }

    private func advanceModeAfterCapture() {
        mode = mode.next
        translationController.configure(for: mode)
        DebugLogger.log("advance mode for next capture -> \(mode.shortLabel)")
    }

    private func markCaptureCycleIfNeeded() {
        if phase == .idle || phase == .failed {
            shouldAdvanceModeAfterCurrentCapture = true
        }
    }

    private func finishCaptureCycle(advance: Bool) {
        defer { shouldAdvanceModeAfterCurrentCapture = false }
        guard advance, shouldAdvanceModeAfterCurrentCapture else { return }
        advanceModeAfterCapture()
    }

    func setMode(_ newMode: InputMode) {
        guard mode != newMode else { return }
        cleanupDirectSession()
        mode = newMode
        translationController.configure(for: mode)
        DebugLogger.log("set mode -> \(mode.shortLabel)")

        if phase == .idle {
            previewText = "\(mode.displayName) 已启用"
        }
    }

    func quitApplication() {
        DebugLogger.log("quit application requested")
        NSApp.terminate(nil)
    }

    func updateHotKeyKey(_ key: HotKeyKey) {
        guard hotKeyConfiguration.key != key else { return }
        hotKeyConfiguration.key = key
        persistHotKeyConfiguration()
        installHotKeys()
        previewText = "全局热键已更新为 \(hotKeyConfiguration.displayString)"
        DebugLogger.log("hotkey key updated -> \(hotKeyConfiguration.displayString)")
    }

    func isHotKeyModifierEnabled(_ modifier: HotKeyModifier) -> Bool {
        hotKeyConfiguration.contains(modifier)
    }

    func toggleHotKeyModifier(_ modifier: HotKeyModifier) {
        var nextConfiguration = hotKeyConfiguration
        nextConfiguration.setModifier(modifier, enabled: !nextConfiguration.contains(modifier))

        guard nextConfiguration.hasAnyModifier else {
            previewText = "全局热键至少保留一个修饰键。"
            return
        }

        hotKeyConfiguration = nextConfiguration
        persistHotKeyConfiguration()
        installHotKeys()
        previewText = "全局热键已更新为 \(hotKeyConfiguration.displayString)"
        DebugLogger.log("hotkey modifiers updated -> \(hotKeyConfiguration.displayString)")
    }

    func resetHotKeyConfiguration() {
        hotKeyConfiguration = .defaultValue
        persistHotKeyConfiguration()
        installHotKeys()
        previewText = "全局热键已恢复默认：\(hotKeyConfiguration.displayString)"
        DebugLogger.log("hotkey reset -> \(hotKeyConfiguration.displayString)")
    }

    func toggleCapture() {
        DebugLogger.log("toggle capture phase=\(String(describing: phase))")
        markCaptureCycleIfNeeded()

        if activeCaptureEngine == .customTranscription {
            if phase == .preparing {
                previewText = "仍在准备语音资源，请稍等。"
                return
            }

            if phase == .listening {
                speechRecognizer.stopRecording()
                return
            }
        }

        if mode.usesSystemDictation {
            toggleSystemDictation()
            return
        }

        if phase == .preparing {
            previewText = "仍在准备语音资源，请稍等。"
            return
        }

        if phase == .listening {
            speechRecognizer.stopRecording()
            return
        }

        Task {
            await startCapture()
        }
    }

    private func toggleSystemDictation() {
        do {
            switch phase {
            case .idle, .failed, .processing:
                try beginDirectDictation()
            case .preparing, .listening:
                try endDirectDictation()
            }
        } catch {
            handleError(error)
        }
    }

    private func beginDirectDictation() throws {
        directMonitorTask?.cancel()
        directFinalizeTask?.cancel()
        directMonitorTask = nil
        directFinalizeTask = nil

        if let appInfo = try? frontmostInspector.inspect() {
            DebugLogger.log("frontmost app=\(appInfo.name) dictationMenu=\(appInfo.supportsSystemDictationMenu) focusedText=\(appInfo.hasFocusedTextInput)")

            if !appInfo.supportsSystemDictationMenu || !appInfo.hasFocusedTextInput {
                phase = .preparing
                if !appInfo.supportsSystemDictationMenu {
                    previewText = "当前前台应用“\(appInfo.name)”不支持系统听写，已切换为兼容识别模式。"
                } else {
                    previewText = "当前前台应用“\(appInfo.name)”无法回填听写结果，已切换为兼容识别模式。"
                }
                DebugLogger.log("direct fallback custom capture app=\(appInfo.name) reason=\(!appInfo.supportsSystemDictationMenu ? "noMenu" : "noFocusedText")")
                Task { [weak self] in
                    await self?.startCapture(using: .customTranscription)
                }
                return
            }
        }

        if let context = try? injector.focusedContext(),
           let snapshot = context.snapshot() {
            directSession = DirectDictationSession(
                context: context,
                initialSnapshot: snapshot
            )
            directFallbackBaseline = snapshot.value
            DebugLogger.log("direct session snapshot captured")
        } else {
            directSession = nil
            directFallbackBaseline = (try? injector.snapshotBySelectingAll()) ?? ""
            DebugLogger.log("direct session snapshot unavailable")
            DebugLogger.log("direct fallback baseline chars=\((directFallbackBaseline as NSString).length)")
        }

        try systemDictation.toggle()
        activeCaptureEngine = .systemDictation
        phase = .listening
        directFallbackIdleSince = nil
        if directSession == nil {
            previewText = "系统听写已启动；结束后会尝试抓取整段文本并自动整理。"
        } else {
            previewText = "系统听写已启动，请直接对着麦克风说话。"
        }
        startDirectMonitor()
    }

    private func endDirectDictation() throws {
        try systemDictation.toggle()
        phase = .processing
        previewText = "正在整理系统听写结果..."

        directFinalizeTask?.cancel()
        directFinalizeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            await self?.finalizeDirectDictation(force: true)
        }
    }

    private func installHotKeys() {
        hotKeys.unregisterAll()
        hotKeys.register(
            id: 1,
            keyCode: hotKeyConfiguration.key.carbonKeyCode,
            modifiers: hotKeyConfiguration.carbonModifiers
        ) { [weak self] in
            DebugLogger.log("hotkey pressed capture")
            Task { @MainActor in
                self?.toggleCapture()
            }
        }
    }

    private func persistHotKeyConfiguration() {
        guard let encoded = try? JSONEncoder().encode(hotKeyConfiguration) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.hotKeyDefaultsKey)
    }

    private static func loadHotKeyConfiguration() -> HotKeyConfiguration {
        guard let encoded = UserDefaults.standard.data(forKey: hotKeyDefaultsKey),
              let configuration = try? JSONDecoder().decode(HotKeyConfiguration.self, from: encoded),
              configuration.hasAnyModifier else {
            return .defaultValue
        }

        return configuration
    }

    private func startCapture() async {
        await startCapture(using: .customTranscription)
    }

    private func startCapture(using engine: CaptureEngine) async {
        do {
            DebugLogger.log("start capture begin")
            try await permissions.ensureCapturePermissions()
            refreshPermissions()

            translationController.configure(for: mode)
            activeCaptureEngine = engine
            phase = .preparing
            previewText = "正在准备语音识别..."
            lastError = ""
            injectionSession = try? injector.beginSession()
            DebugLogger.log("start capture injectionSession=\(injectionSession != nil)")
            DebugLogger.log("start capture granted locale=\(mode.sourceLocale.identifier)")

            try await speechRecognizer.startRecording(
                locale: mode.sourceLocale
            ) { [weak self] partialText in
                Task { @MainActor in
                    await self?.handlePartial(partialText)
                }
            } onComplete: { [weak self] finalText in
                Task { @MainActor in
                    await self?.commit(finalText)
                }
            } onError: { [weak self] error in
                Task { @MainActor in
                    self?.handleError(error)
                }
            }
            phase = .listening
            if previewText == "正在准备语音识别..." {
                previewText = "正在听..."
            }
            DebugLogger.log("start capture recording started")
        } catch {
            DebugLogger.log("start capture error \(error.localizedDescription)")
            handleError(error)
        }
    }

    private func handlePartial(_ text: String) async {
        guard phase == .listening || phase == .preparing else { return }
        DebugLogger.log("partial text=\(text)")

        if phase == .preparing {
            phase = .listening
        }

        let rendered = await pipeline.renderPreview(text, mode: mode)
        previewText = rendered.isEmpty ? "正在听..." : rendered

        if let injectionSession, !rendered.isEmpty {
            do {
                try injectionSession.update(text: rendered)
                DebugLogger.log("live inject success")
            } catch {
                self.injectionSession = nil
                DebugLogger.log("live inject error \(error.localizedDescription)")
            }
        }
    }

    private func commit(_ rawText: String) async {
        DebugLogger.log("commit raw=\(rawText)")
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .idle
            previewText = "没有检测到有效语音。"
            injectionSession = nil
            activeCaptureEngine = nil
            finishCaptureCycle(advance: true)
            DebugLogger.log("commit ignored empty")
            return
        }

        phase = .processing
        let finalText = await pipeline.finalize(rawText, mode: mode)
        DebugLogger.log("commit final=\(finalText)")

        do {
            if let injectionSession {
                try injectionSession.update(text: finalText)
            } else {
                try injector.insert(finalText)
            }
            committedText = finalText
            previewText = finalText
            phase = .idle
            injectionSession = nil
            activeCaptureEngine = nil
            finishCaptureCycle(advance: true)
            DebugLogger.log("inject success")
        } catch {
            injectionSession = nil
            activeCaptureEngine = nil
            DebugLogger.log("inject error \(error.localizedDescription)")
            handleError(error)
        }
    }

    private func handleError(_ error: Error) {
        let shouldAdvance = activeCaptureEngine != nil
        phase = .failed
        lastError = error.localizedDescription
        previewText = error.localizedDescription
        injectionSession = nil
        activeCaptureEngine = nil
        cleanupDirectSession()
        finishCaptureCycle(advance: shouldAdvance)
        DebugLogger.log("handle error \(error.localizedDescription)")
    }

    private func prewarmSpeechAssets() {
        Task { @MainActor in
            DebugLogger.log("prewarm speech assets begin")
            await speechRecognizer.prewarm(locale: Locale(identifier: "zh-CN"))
            await speechRecognizer.prewarm(locale: Locale(identifier: "en-US"))
            DebugLogger.log("prewarm speech assets done")
        }
    }

    private func startDirectMonitor() {
        directMonitorTask?.cancel()
        directMonitorTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                await self.tickDirectMonitor()
            }
        }
    }

    private func tickDirectMonitor() async {
        guard mode.usesSystemDictation, phase == .listening || phase == .processing else {
            return
        }

        guard let directSession else {
            if phase == .listening {
                await finalizeDirectDictationFallback(force: false)
            }
            return
        }

        if let change = directSession.poll() {
            let polishedPreview = SentencePolisher().polishPreview(
                change.text,
                language: mode.outputLanguage
            )
            if !polishedPreview.isEmpty {
                previewText = polishedPreview
            }
            DebugLogger.log("direct monitor change=\(change.text)")
        }

        if phase == .listening, directSession.shouldFinalize(stableFor: 1.15) {
            await finalizeDirectDictation(force: false)
        }
    }

    private func finalizeDirectDictation(force: Bool) async {
        directFinalizeTask?.cancel()
        directFinalizeTask = nil

        guard let directSession else {
            await finalizeDirectDictationFallback(force: force)
            return
        }

        _ = directSession.poll()
        guard force || directSession.shouldFinalize(stableFor: 1.15) else {
            return
        }

        guard let change = directSession.currentChange(),
              !change.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cleanupDirectSession()
            phase = .idle
            activeCaptureEngine = nil
            previewText = "没有检测到有效语音。"
            finishCaptureCycle(advance: true)
            DebugLogger.log("direct finalize empty")
            return
        }

        phase = .processing
        DebugLogger.log("direct finalize raw=\(change.text)")
        let finalText = await pipeline.finalizeDirect(change.text, language: mode.outputLanguage)
        DebugLogger.log("direct finalize rewritten=\(finalText)")

        do {
            try directSession.replaceCurrentChange(with: finalText)
            committedText = finalText
            previewText = finalText
            phase = .idle
            activeCaptureEngine = nil
            cleanupDirectSession()
            finishCaptureCycle(advance: true)
            DebugLogger.log("direct finalize inject success")
        } catch {
            cleanupDirectSession()
            DebugLogger.log("direct finalize inject error \(error.localizedDescription)")
            handleError(error)
        }
    }

    private func finalizeDirectDictationFallback(force: Bool) async {
        if !force {
            let isDictationActive = systemDictation.isActiveInFrontmostApp()
            if isDictationActive {
                directFallbackIdleSince = nil
                return
            }

            if directFallbackIdleSince == nil {
                directFallbackIdleSince = Date()
                return
            }

            guard let directFallbackIdleSince,
                  Date().timeIntervalSince(directFallbackIdleSince) >= 0.75 else {
                return
            }
        }

        phase = .processing

        do {
            let fullText = try injector.snapshotBySelectingAll()
            let baseline = directFallbackBaseline
            let rawChange = DirectDictationSession.diff(from: baseline, to: fullText)?.text ?? fullText
            let normalized = rawChange.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalized.isEmpty else {
                cleanupDirectSession()
                phase = .idle
                activeCaptureEngine = nil
                previewText = "没有检测到有效语音。"
                finishCaptureCycle(advance: true)
                DebugLogger.log("direct fallback finalize empty")
                return
            }

            DebugLogger.log("direct fallback raw=\(normalized)")
            let finalText = await pipeline.finalizeDirect(normalized, language: mode.outputLanguage)

            let replacementText: String
            if let change = DirectDictationSession.diff(from: baseline, to: fullText) {
                replacementText = (fullText as NSString).replacingCharacters(in: change.rangeInCurrentText, with: finalText)
            } else {
                replacementText = finalText
            }

            try injector.replaceAll(inFocusedElementWith: replacementText)
            committedText = finalText
            previewText = finalText
            phase = .idle
            activeCaptureEngine = nil
            cleanupDirectSession()
            finishCaptureCycle(advance: true)
            DebugLogger.log("direct fallback inject success")
        } catch {
            activeCaptureEngine = nil
            cleanupDirectSession()
            DebugLogger.log("direct fallback inject error \(error.localizedDescription)")
            handleError(error)
        }
    }

    private func cleanupDirectSession() {
        directMonitorTask?.cancel()
        directFinalizeTask?.cancel()
        directMonitorTask = nil
        directFinalizeTask = nil
        directSession = nil
        directFallbackBaseline = ""
        directFallbackIdleSince = nil
    }
}
