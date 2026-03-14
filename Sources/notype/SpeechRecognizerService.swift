@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

enum SpeechRecognizerError: LocalizedError {
    case recognizerUnavailable
    case recordingAlreadyRunning
    case transcriptionAssetsUnavailable
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "当前语言的语音识别器不可用。"
        case .recordingAlreadyRunning:
            return "语音识别已经在运行。"
        case .transcriptionAssetsUnavailable:
            return "当前语言的离线听写资源不可用。"
        case .audioConversionFailed:
            return "音频格式转换失败。"
        }
    }
}

private final class RecognitionRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }
}

final class SpeechRecognizerService: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceWorkItem: DispatchWorkItem?
    private var forcedCompletionWorkItem: DispatchWorkItem?
    private var finalCallback: ((String) -> Void)?
    private var completionDelivered = false
    private var latestTranscript = ""
    private var modernCoordinator: AnyObject?
    private var modernStopper: (() -> Void)?

    func prewarm(locale: Locale) async {
        DebugLogger.log("speech prewarm locale=\(locale.identifier)")

        if let recognizer = SFSpeechRecognizer(locale: locale) {
            DebugLogger.log("speech prewarm legacy available=\(recognizer.isAvailable) locale=\(locale.identifier)")
        }
    }

    func startRecording(
        locale: Locale,
        onPartial: @Sendable @escaping (String) -> Void,
        onComplete: @Sendable @escaping (String) -> Void,
        onError: @Sendable @escaping (Error) -> Void
    ) async throws {
        DebugLogger.log("speech start requested locale=\(locale.identifier)")

        guard recognitionTask == nil, modernCoordinator == nil else {
            throw SpeechRecognizerError.recordingAlreadyRunning
        }

        latestTranscript = ""
        completionDelivered = false
        finalCallback = onComplete

        try await startLegacyRecognition(
            locale: locale,
            onPartial: onPartial,
            onComplete: onComplete,
            onError: onError
        )
    }

    func stopRecording() {
        DebugLogger.log("speech stop requested")

        if let modernStopper {
            modernStopper()
            scheduleForcedCompletion()
            return
        }

        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        scheduleForcedCompletion()
    }

    private func startLegacyRecognition(
        locale: Locale,
        onPartial: @Sendable @escaping (String) -> Void,
        onComplete: @Sendable @escaping (String) -> Void,
        onError: @Sendable @escaping (Error) -> Void
    ) async throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechRecognizerError.recognizerUnavailable
        }

        DebugLogger.log("legacy recognizer available onDevice=\(recognizer.supportsOnDeviceRecognition)")

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.taskHint = .dictation
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        request.addsPunctuation = true
        recognitionRequest = request
        let requestBox = RecognitionRequestBox(request)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            requestBox.request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        DebugLogger.log("legacy audio engine started")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let bridgedError = error as NSError?
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            guard let self else { return }

            if let bridgedError {
                self.finishSession()
                DebugLogger.log("legacy speech error \(bridgedError.localizedDescription)")
                onError(bridgedError)
                return
            }

            guard let transcript else { return }
            let text = transcript
            self.latestTranscript = text
            onPartial(text)
            self.scheduleSilenceTimeout()
            DebugLogger.log("legacy speech result final=\(isFinal) text=\(text)")

            if isFinal {
                self.deliverCompletion(text)
            }
        }
    }

    private func scheduleSilenceTimeout() {
        silenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finalizeBecauseOfSilence()
        }
        silenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func finalizeBecauseOfSilence() {
        DebugLogger.log("speech silence timeout")
        stopRecording()
    }

    private func scheduleForcedCompletion() {
        let fallbackText = latestTranscript
        forcedCompletionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.completionDelivered else { return }
            DebugLogger.log("speech forced completion text=\(fallbackText)")
            self.deliverCompletion(fallbackText)
        }
        forcedCompletionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func deliverCompletion(_ text: String) {
        guard !completionDelivered else { return }
        completionDelivered = true
        let callback = finalCallback
        finishSession()
        callback?(text)
    }

    private func finishSession() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        forcedCompletionWorkItem?.cancel()
        forcedCompletionWorkItem = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        modernStopper = nil
        modernCoordinator = nil
        finalCallback = nil

        DebugLogger.log("speech finish session")
    }
}

@available(macOS 26.0, *)
@MainActor
final class ModernDictationCoordinator {
    private let locale: Locale
    private let onPartial: (String) -> Void
    private let onFinal: (String) -> Void
    private let onError: (Error) -> Void

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var resultsTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    init(
        locale: Locale,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.locale = locale
        self.onPartial = onPartial
        self.onFinal = onFinal
        self.onError = onError
    }

    static func prewarm(locale: Locale) async throws {
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        let status = await AssetInventory.status(forModules: [transcriber])
        DebugLogger.log("modern prewarm asset status=\(String(describing: status)) locale=\(locale.identifier)")

        switch status {
        case .unsupported:
            throw SpeechRecognizerError.transcriptionAssetsUnavailable
        case .supported:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                DebugLogger.log("modern prewarm downloading asset locale=\(locale.identifier)")
                try await request.downloadAndInstall()
            }
        case .downloading, .installed:
            break
        @unknown default:
            break
        }
    }

    func start() async throws {
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        let status = await AssetInventory.status(forModules: [transcriber])
        DebugLogger.log("modern asset status=\(String(describing: status))")

        switch status {
        case .unsupported:
            throw SpeechRecognizerError.transcriptionAssetsUnavailable
        case .supported:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                DebugLogger.log("modern downloading transcription asset")
                try await request.downloadAndInstall()
            }
        case .downloading, .installed:
            break
        @unknown default:
            break
        }

        let inputNode = audioEngine.inputNode
        let naturalFormat = inputNode.outputFormat(forBus: 0)
        let preferredFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: naturalFormat
        ) ?? naturalFormat

        converter = AVAudioConverter(from: naturalFormat, to: preferredFormat)
        targetFormat = preferredFormat
        self.transcriber = transcriber

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: preferredFormat)
        DebugLogger.log("modern analyzer prepared sampleRate=\(preferredFormat.sampleRate)")

        let inputStream = AsyncStream(AnalyzerInput.self, bufferingPolicy: .unbounded) { continuation in
            self.inputContinuation = continuation
        }

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await MainActor.run {
                        self.onPartial(text)
                        DebugLogger.log("modern speech result final=\(result.isFinal) text=\(text)")
                        if result.isFinal {
                            self.onFinal(text)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    DebugLogger.log("modern results error \(error.localizedDescription)")
                    self.onError(error)
                }
            }
        }

        analyzerTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await analyzer.start(inputSequence: inputStream)
            } catch {
                await MainActor.run {
                    DebugLogger.log("modern analyzer error \(error.localizedDescription)")
                    self.onError(error)
                }
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: naturalFormat) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in
                do {
                    let outputBuffer = try self.convert(buffer: buffer)
                    self.inputContinuation?.yield(AnalyzerInput(buffer: outputBuffer))
                } catch {
                    DebugLogger.log("modern audio conversion error \(error.localizedDescription)")
                    self.onError(error)
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        DebugLogger.log("modern audio engine started")
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()

        Task { [weak self] in
            guard let self, let analyzer = self.analyzer else { return }
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await MainActor.run {
                    DebugLogger.log("modern finalize error \(error.localizedDescription)")
                }
            }
        }
    }

    private func convert(buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter, let targetFormat else {
            return buffer
        }

        if buffer.format == targetFormat {
            return buffer
        }

        let estimatedLength = AVAudioFrameCount(
            (Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate).rounded(.up)
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: max(estimatedLength, 1024)
        ) else {
            throw SpeechRecognizerError.audioConversionFailed
        }

        final class ConversionState {
            var remaining = true
        }

        let state = ConversionState()
        var conversionError: NSError?

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if state.remaining {
                state.remaining = false
                outStatus.pointee = .haveData
                return buffer
            } else {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        if let conversionError {
            throw conversionError
        }

        guard status != .error else {
            throw SpeechRecognizerError.audioConversionFailed
        }

        return outputBuffer
    }
}
