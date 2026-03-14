import ApplicationServices
import AppKit
import Carbon
import Foundation

enum TextInjectionError: LocalizedError {
    case noFocusedElement
    case injectionFailed
    case elementNotEditable

    var errorDescription: String? {
        switch self {
        case .noFocusedElement:
            return "没有找到当前焦点输入区域。"
        case .injectionFailed:
            return "无法把文本写入当前应用，请确认目标应用允许辅助功能输入。"
        case .elementNotEditable:
            return "当前焦点区域不支持实时文本替换。"
        }
    }
}

struct FocusedTextSnapshot {
    let value: String
    let selection: NSRange
}

final class FocusedTextContext {
    private let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    func snapshot() -> FocusedTextSnapshot? {
        var valueObject: CFTypeRef?
        var rangeObject: CFTypeRef?

        let hasValue = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueObject
        ) == .success

        let hasRange = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeObject
        ) == .success

        guard hasValue,
              hasRange,
              let currentValue = valueObject as? String,
              let rangeObject else {
            DebugLogger.log("inject context unavailable hasValue=\(hasValue) hasRange=\(hasRange)")
            return nil
        }

        let rangeAXValue = rangeObject as! AXValue
        var range = CFRange()

        guard AXValueGetValue(rangeAXValue, .cfRange, &range) else {
            DebugLogger.log("inject context invalid range")
            return nil
        }

        let selection = NSRange(location: range.location, length: range.length)
        let currentNSString = currentValue as NSString
        guard NSMaxRange(selection) <= currentNSString.length else {
            DebugLogger.log("inject context selection out of bounds")
            return nil
        }

        return FocusedTextSnapshot(
            value: currentValue,
            selection: selection
        )
    }

    func replace(range: NSRange, with text: String) throws {
        guard let snapshot = snapshot() else {
            throw TextInjectionError.injectionFailed
        }

        let currentNSString = snapshot.value as NSString
        guard NSMaxRange(range) <= currentNSString.length else {
            throw TextInjectionError.injectionFailed
        }

        let replacement = currentNSString.replacingCharacters(in: range, with: text)
        try setValue(replacement, caretLocation: range.location + (text as NSString).length)
    }

    func replace(selectionRange: NSRange, in originalValue: String, with text: String) throws {
        let originalNSString = originalValue as NSString
        guard NSMaxRange(selectionRange) <= originalNSString.length else {
            throw TextInjectionError.injectionFailed
        }

        let replacement = originalNSString.replacingCharacters(in: selectionRange, with: text)
        try setValue(replacement, caretLocation: selectionRange.location + (text as NSString).length)
    }

    private func setValue(_ replacement: String, caretLocation: Int) throws {
        let setValueStatus = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            replacement as CFTypeRef
        )

        guard setValueStatus == .success else {
            DebugLogger.log("inject context set value failed status=\(setValueStatus.rawValue)")
            throw TextInjectionError.elementNotEditable
        }

        var caretRange = CFRange(location: caretLocation, length: 0)
        if let caretValue = AXValueCreate(.cfRange, &caretRange) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                caretValue
            )
        }
    }
}

final class GlobalTextInjector {
    func focusedContext() throws -> FocusedTextContext? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?

        let status = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )

        guard status == .success, let focusedElement = focusedObject else {
            DebugLogger.log("inject begin no focused element status=\(status.rawValue)")
            throw TextInjectionError.noFocusedElement
        }

        return FocusedTextContext(element: focusedElement as! AXUIElement)
    }

    func beginSession() throws -> TextInjectionSession? {
        guard let context = try? focusedContext(),
              let snapshot = context.snapshot() else {
            DebugLogger.log("inject session fallback typing")
            return TextInjectionSession(typingFallback: self)
        }

        DebugLogger.log("inject session ready location=\(snapshot.selection.location) length=\(snapshot.selection.length)")
        return TextInjectionSession(context: context, originalSnapshot: snapshot)
    }

    func insert(_ text: String) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        DebugLogger.log("inject begin text=\(normalized)")

        if let session = try? beginSession() {
            try session.update(text: normalized)
            DebugLogger.log("inject via session ok")
            return
        }

        DebugLogger.log("inject fallback unicode")
        try typeUnicode(normalized)
    }

    func snapshotBySelectingAll() throws -> String {
        let pasteboard = NSPasteboard.general
        let preserved = PasteboardSnapshot.capture(from: pasteboard)
        let marker = "NOTYPE-\(UUID().uuidString)"

        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)

        try sendShortcut(keyCode: CGKeyCode(kVK_ANSI_A), modifiers: .maskCommand)
        sleepForUI()
        try sendShortcut(keyCode: CGKeyCode(kVK_ANSI_C), modifiers: .maskCommand)
        sleepForUI()

        let copied = pasteboard.string(forType: .string) ?? ""
        preserved?.restore(to: pasteboard)

        try? sendShortcut(keyCode: CGKeyCode(kVK_RightArrow), modifiers: [])
        sleepForUI()

        if copied == marker {
            DebugLogger.log("inject snapshot clipboard empty")
            return ""
        }

        DebugLogger.log("inject snapshot clipboard chars=\((copied as NSString).length)")
        return copied
    }

    func replaceAll(inFocusedElementWith text: String) throws {
        let pasteboard = NSPasteboard.general
        let preserved = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try sendShortcut(keyCode: CGKeyCode(kVK_ANSI_A), modifiers: .maskCommand)
        sleepForUI()
        try sendShortcut(keyCode: CGKeyCode(kVK_ANSI_V), modifiers: .maskCommand)
        sleepForUI()

        preserved?.restore(to: pasteboard)
        DebugLogger.log("inject replaceAll chars=\((text as NSString).length)")
    }

    fileprivate func typeUnicode(_ text: String) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            DebugLogger.log("inject unicode source unavailable")
            throw TextInjectionError.injectionFailed
        }

        let scalars = Array(text.utf16)
        for isKeyDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: isKeyDown
            ) else {
                throw TextInjectionError.injectionFailed
            }

            event.keyboardSetUnicodeString(stringLength: scalars.count, unicodeString: scalars)
            event.post(tap: .cghidEventTap)
        }
    }

    fileprivate func deleteBackward(count: Int) throws {
        guard count > 0 else { return }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw TextInjectionError.injectionFailed
        }

        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: false) else {
                throw TextInjectionError.injectionFailed
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func sendShortcut(keyCode: CGKeyCode, modifiers: CGEventFlags) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw TextInjectionError.injectionFailed
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func sleepForUI() {
        Thread.sleep(forTimeInterval: 0.09)
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            return PasteboardSnapshot(items: [])
        }

        let items = pasteboardItems.map { item in
            [NSPasteboard.PasteboardType: Data](uniqueKeysWithValues: item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            })
        }

        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        guard !items.isEmpty else { return }

        let restoredItems = items.map { snapshot -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshot {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}

final class TextInjectionSession {
    private let applyUpdate: (String) throws -> Void

    init(context: FocusedTextContext, originalSnapshot: FocusedTextSnapshot) {
        self.applyUpdate = { text in
            try context.replace(
                selectionRange: originalSnapshot.selection,
                in: originalSnapshot.value,
                with: text
            )
        }
    }

    init(typingFallback injector: GlobalTextInjector) {
        let state = TypingFallbackState()
        self.applyUpdate = { text in
            let previous = state.renderedText
            if text == previous {
                return
            }

            let replacementLength = (previous as NSString).length
            if replacementLength > 0 {
                try injector.deleteBackward(count: replacementLength)
            }
            if !text.isEmpty {
                try injector.typeUnicode(text)
            }
            state.renderedText = text
        }
    }

    func update(text: String) throws {
        try applyUpdate(text)
    }
}

private final class TypingFallbackState {
    var renderedText = ""
}
