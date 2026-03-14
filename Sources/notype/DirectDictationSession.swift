import Foundation

struct DirectDictationChange {
    let rangeInCurrentText: NSRange
    let text: String
}

@MainActor
final class DirectDictationSession {
    let context: FocusedTextContext
    let initialSnapshot: FocusedTextSnapshot

    private(set) var latestSnapshot: FocusedTextSnapshot
    private var lastChangeAt: Date?

    init(context: FocusedTextContext, initialSnapshot: FocusedTextSnapshot) {
        self.context = context
        self.initialSnapshot = initialSnapshot
        self.latestSnapshot = initialSnapshot
    }

    func poll() -> DirectDictationChange? {
        guard let snapshot = context.snapshot() else {
            return nil
        }

        if snapshot.value != latestSnapshot.value {
            latestSnapshot = snapshot
            lastChangeAt = Date()
        } else {
            latestSnapshot = snapshot
        }

        return currentChange()
    }

    func currentChange() -> DirectDictationChange? {
        Self.diff(from: initialSnapshot.value, to: latestSnapshot.value)
    }

    func shouldFinalize(stableFor delay: TimeInterval) -> Bool {
        guard let lastChangeAt else { return false }
        return Date().timeIntervalSince(lastChangeAt) >= delay
    }

    func replaceCurrentChange(with text: String) throws {
        guard let change = currentChange() else { return }
        try context.replace(range: change.rangeInCurrentText, with: text)
    }

    static func diff(from oldValue: String, to newValue: String) -> DirectDictationChange? {
        guard oldValue != newValue else { return nil }

        let oldNSString = oldValue as NSString
        let newNSString = newValue as NSString

        let prefixLength = commonPrefixLength(oldValue, newValue)
        let maxSuffix = min(oldNSString.length, newNSString.length) - prefixLength
        let suffixLength = commonSuffixLength(oldValue, newValue, maxLength: maxSuffix)

        let changedLocation = prefixLength
        let changedLength = newNSString.length - prefixLength - suffixLength
        guard changedLength >= 0 else { return nil }

        let range = NSRange(location: changedLocation, length: changedLength)
        let changedText = newNSString.substring(with: range)

        return DirectDictationChange(
            rangeInCurrentText: range,
            text: changedText
        )
    }

    private static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        var left = lhs.startIndex
        var right = rhs.startIndex

        while left < lhs.endIndex, right < rhs.endIndex, lhs[left] == rhs[right] {
            count += lhs[left].utf16.count
            left = lhs.index(after: left)
            right = rhs.index(after: right)
        }

        return count
    }

    private static func commonSuffixLength(_ lhs: String, _ rhs: String, maxLength: Int) -> Int {
        var count = 0
        var left = lhs.endIndex
        var right = rhs.endIndex

        while count < maxLength,
              left > lhs.startIndex,
              right > rhs.startIndex {
            let previousLeft = lhs.index(before: left)
            let previousRight = rhs.index(before: right)

            guard lhs[previousLeft] == rhs[previousRight] else {
                break
            }

            count += lhs[previousLeft].utf16.count
            left = previousLeft
            right = previousRight
        }

        return count
    }
}
