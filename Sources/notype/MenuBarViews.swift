import SwiftUI
import Translation

struct StatusItemLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)

            Text(model.mode.shortLabel)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private var indicatorColor: Color {
        switch model.phase {
        case .idle:
            return .green
        case .preparing:
            return .blue
        case .listening:
            return .red
        case .processing:
            return .orange
        case .failed:
            return .yellow
        }
    }
}

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            previewCard
            modeSection
            permissionSection
            footer
        }
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NoType")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text(model.statusSummary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("实时预览")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(model.previewText)
                .font(.system(size: 14, weight: .regular))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor))
                )
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("输入模式")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(InputMode.allCases, id: \.self) { mode in
                Button {
                    model.setMode(mode)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                            Text(mode.hotKeyHint)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if mode == model.mode {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
            }
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("权限状态")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            PermissionRow(title: "辅助功能", granted: model.accessibilityGranted) {
                model.requestAccessibilityAccess()
            }
            PermissionRow(title: "麦克风", granted: model.microphoneGranted)
            PermissionRow(title: "语音识别", granted: model.speechGranted)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.menuHint)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Button(model.phase == .listening ? "结束听写" : "开始听写") {
                    model.toggleCapture()
                }
                .keyboardShortcut(.space, modifiers: [.control, .option])
            }

            HStack {
                Spacer()
                Button("退出 NoType") {
                    model.quitApplication()
                }
                .keyboardShortcut("q", modifiers: [.command])
            }

            Text("开始/结束：Control + Option + Space")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text("每次完成后自动切换到下一个模式：中文 -> 英文 -> 中转英 -> 英转中")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(granted ? "已授权" : "未授权")
                .foregroundStyle(granted ? .green : .orange)

            if let action, !granted {
                Button("授权", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .font(.system(size: 12))
    }
}

struct TranslationHostView: View {
    @ObservedObject var controller: TranslationController

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(controller.configuration) { session in
                await controller.bind(session)
            }
    }
}
