import Foundation

enum SystemDictationError: LocalizedError {
    case scriptFailed(String)
    case menuItemNotFound
    case automationDenied

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let message):
            return "系统听写脚本执行失败：\(message)"
        case .menuItemNotFound:
            return "当前前台应用没有可用的“开始听写”菜单项。"
        case .automationDenied:
            return "NoType 没有“自动化”权限来控制 System Events。请到 系统设置 > 隐私与安全性 > 自动化，开启 NoType 对 System Events 的控制。"
        }
    }
}

final class SystemDictationController {
    func toggle() throws {
        let script = """
        tell application "System Events"
            set frontProcess to first application process whose frontmost is true
            set editMenuNames to {"编辑", "Edit"}
            set dictationItemNames to {"开始听写", "Start Dictation", "Start Dictation…", "Start Dictation..."}

            repeat with editMenuName in editMenuNames
                try
                    set editMenuBarItem to menu bar item (contents of editMenuName) of menu bar 1 of frontProcess
                    tell editMenuBarItem
                        repeat with dictationItemName in dictationItemNames
                            try
                                click menu item (contents of dictationItemName) of menu 1
                                return name of frontProcess
                            end try
                        end repeat
                    end tell
                end try
            end repeat
        end tell

        error "DICTATION_MENU_NOT_FOUND"
        """

        var errorInfo: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&errorInfo)

        if let result {
            DebugLogger.log("system dictation menu clicked app=\(result.stringValue ?? "unknown")")
            return
        }

        let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "unknown"
        DebugLogger.log("system dictation script error=\(message)")

        if message.contains("DICTATION_MENU_NOT_FOUND") {
            throw SystemDictationError.menuItemNotFound
        }

        if message.localizedCaseInsensitiveContains("Not authorized to send Apple events") {
            throw SystemDictationError.automationDenied
        }

        throw SystemDictationError.scriptFailed(message)
    }

    func isActiveInFrontmostApp() -> Bool {
        let script = """
        tell application "System Events"
            set frontProcess to first application process whose frontmost is true
            set editMenuNames to {"编辑", "Edit"}
            set activeItemNames to {"停止听写", "Stop Dictation", "Stop Dictation…", "Stop Dictation..."}

            repeat with editMenuName in editMenuNames
                try
                    set editMenuBarItem to menu bar item (contents of editMenuName) of menu bar 1 of frontProcess
                    tell editMenuBarItem
                        repeat with itemName in activeItemNames
                            try
                                set _ to menu item (contents of itemName) of menu 1
                                return "true"
                            end try
                        end repeat
                    end tell
                end try
            end repeat
        end tell

        return "false"
        """

        var errorInfo: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&errorInfo)

        if let value = result?.stringValue?.lowercased() {
            return value == "true"
        }

        let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "unknown"
        DebugLogger.log("system dictation active check error=\(message)")
        return false
    }
}
