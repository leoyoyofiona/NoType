import Foundation

struct FrontmostAppInfo {
    let name: String
    let supportsSystemDictationMenu: Bool
    let hasFocusedTextInput: Bool
}

enum FrontmostAppError: LocalizedError {
    case inspectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .inspectionFailed(let message):
            return "无法检查当前前台应用：\(message)"
        }
    }
}

final class FrontmostAppInspector {
    func inspect() throws -> FrontmostAppInfo {
        let script = """
        tell application "System Events"
            set frontProcess to first application process whose frontmost is true
            set appName to name of frontProcess

            set hasTextInput to false
            try
                set focusedElement to value of attribute "AXFocusedUIElement" of frontProcess
                try
                    set _ to value of attribute "AXValue" of focusedElement
                    set hasTextInput to true
                end try
            end try

            set supportsDictation to false
            set editMenuNames to {"编辑", "Edit"}
            set dictationItemNames to {"开始听写", "Start Dictation", "Start Dictation…", "Start Dictation..."}

            repeat with editMenuName in editMenuNames
                try
                    set editMenuBarItem to menu bar item (contents of editMenuName) of menu bar 1 of frontProcess
                    tell editMenuBarItem
                        repeat with dictationItemName in dictationItemNames
                            try
                                set _ to menu item (contents of dictationItemName) of menu 1
                                set supportsDictation to true
                                exit repeat
                            end try
                        end repeat
                    end tell
                end try
                if supportsDictation then exit repeat
            end repeat

            return appName & "||" & (supportsDictation as string) & "||" & (hasTextInput as string)
        end tell
        """

        var errorInfo: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&errorInfo)

        guard let payload = result?.stringValue else {
            let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "unknown"
            throw FrontmostAppError.inspectionFailed(message)
        }

        let parts = payload.components(separatedBy: "||")
        guard parts.count == 3 else {
            throw FrontmostAppError.inspectionFailed("unexpected payload")
        }

        return FrontmostAppInfo(
            name: parts[0],
            supportsSystemDictationMenu: parts[1].lowercased() == "true",
            hasFocusedTextInput: parts[2].lowercased() == "true"
        )
    }
}
