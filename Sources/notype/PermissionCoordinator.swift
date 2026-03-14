import ApplicationServices
import AVFoundation
import Foundation
import Speech

enum PermissionError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case accessibilityDenied
    case speechUsageDescriptionMissing
    case installedAppRequired

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "没有麦克风权限。请在系统设置里允许 NoType 访问麦克风。"
        case .speechDenied:
            return "没有语音识别权限。请在系统设置里允许 NoType 使用语音识别。"
        case .accessibilityDenied:
            return "没有辅助功能权限。全局输入需要在系统设置里授权 NoType。"
        case .speechUsageDescriptionMissing:
            return "当前运行实例缺少语音识别权限说明，NoType 需要以 .app 形式启动。"
        case .installedAppRequired:
            return "你当前打开的是打包产物，不是安装版应用。请先安装，然后从“应用程序”里的 NoType 启动。"
        }
    }
}

@MainActor
final class PermissionCoordinator {
    var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    var hasMicrophoneAccess: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var hasSpeechAccess: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func promptForAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func ensureCapturePermissions() async throws {
        try await ensureSpeechPermission()
        try await ensureMicrophonePermission()
        try await ensureAccessibilityPermission()
    }

    private func ensureAccessibilityPermission() async throws {
        if Bundle.main.bundlePath.contains("/dist/NoType.app") {
            DebugLogger.log("accessibility check blocked because running dist app path=\(Bundle.main.bundlePath)")
            throw PermissionError.installedAppRequired
        }

        if hasAccessibilityAccess {
            return
        }

        DebugLogger.log("accessibility not trusted yet bundleID=\(Bundle.main.bundleIdentifier ?? "nil") path=\(Bundle.main.bundlePath)")
        promptForAccessibilityAccess()

        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(250))
            if hasAccessibilityAccess {
                DebugLogger.log("accessibility became trusted")
                return
            }
        }

        DebugLogger.log("accessibility still untrusted after prompt")
        throw PermissionError.accessibilityDenied
    }

    private func ensureSpeechPermission() async throws {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else {
            DebugLogger.log("speech usage description missing bundlePath=\(Bundle.main.bundlePath)")
            throw PermissionError.speechUsageDescriptionMissing
        }

        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await Self.requestSpeechAuthorization()
            guard granted else { throw PermissionError.speechDenied }
        default:
            throw PermissionError.speechDenied
        }
    }

    private func ensureMicrophonePermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await Self.requestMicrophoneAccess()
            guard granted else { throw PermissionError.microphoneDenied }
        default:
            throw PermissionError.microphoneDenied
        }
    }

    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus == .authorized)
            }
        }
    }

    nonisolated private static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
