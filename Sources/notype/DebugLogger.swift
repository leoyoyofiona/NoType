import Foundation

enum DebugLogger {
    private static let logURL = URL(fileURLWithPath: "/tmp/notype-debug.log")

    static func reset() {
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }

    static func log(_ message: String) {
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    return
                }
            }

            try? data.write(to: logURL)
        }
    }
}
