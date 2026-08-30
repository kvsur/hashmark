import Foundation

struct DocumentStoragePreferenceStore {
    static let storageModeKey = "document-storage-mode"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadMode() -> DocumentStorageMode {
        guard let rawValue = defaults.string(forKey: Self.storageModeKey),
              let mode = DocumentStorageMode(rawValue: rawValue) else {
            return .local
        }
        return mode
    }

    func saveMode(_ mode: DocumentStorageMode) {
        defaults.set(mode.rawValue, forKey: Self.storageModeKey)
    }
}
