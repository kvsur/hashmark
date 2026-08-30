import Foundation

/// Centralizes the user-visible, collision-safe names used whenever distinct bytes
/// must be preserved instead of overwriting an existing document.
nonisolated struct DocumentConflictURLFactory: @unchecked Sendable {
    private let fileManager: FileManager
    private let timestamp: () -> Date
    private let deviceName: String
    private let deviceFallback: String

    init(
        fileManager: FileManager = .default,
        timestamp: @escaping () -> Date = Date.init,
        deviceName: String,
        deviceFallback: String = "Device"
    ) {
        self.fileManager = fileManager
        self.timestamp = timestamp
        self.deviceName = deviceName
        self.deviceFallback = deviceFallback
    }

    func uniqueURL(
        for requestedURL: URL,
        isDirectory: Bool = false,
        label: String = "Conflict"
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let sanitizedDevice = deviceName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let device = sanitizedDevice.isEmpty ? deviceFallback : sanitizedDevice
        let suffix = "\(label) \(formatter.string(from: timestamp())) \(device)"
        let parent = requestedURL.deletingLastPathComponent()
        let ext = isDirectory ? "" : requestedURL.pathExtension
        let base = isDirectory || ext.isEmpty
            ? requestedURL.lastPathComponent
            : requestedURL.deletingPathExtension().lastPathComponent

        func candidate(_ index: Int?) -> URL {
            let indexSuffix = index.map { " \($0)" } ?? ""
            let name = "\(base) (\(suffix))\(indexSuffix)"
            let filename = ext.isEmpty ? name : "\(name).\(ext)"
            return parent.appendingPathComponent(filename, isDirectory: isDirectory)
        }

        var result = candidate(nil)
        var index = 2
        while fileManager.fileExists(atPath: result.path) {
            result = candidate(index)
            index += 1
        }
        return result
    }
}
