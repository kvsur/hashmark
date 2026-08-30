import Foundation

#if DEBUG
/// Explicit, Debug-only real-device checkpoint for S4.6.
///
/// The runner is inert unless `--hashmark-icloud-smoke <token>` is passed. It uses the
/// active cloud controller so the smoke covers the same coordination and download path
/// as the app, while keeping its result outside the user's local Documents library.
@MainActor
enum ICloudDeviceSmokeRunner {
    private static let argument = "--hashmark-icloud-smoke"
    private static let offlineArgument = "--hashmark-icloud-offline-smoke"
    private static let switchLocalArgument = "--hashmark-switch-local"
    private static let resultFilename = "HashmarkS46Smoke.json"
    private static let switchLocalResultFilename = "HashmarkSwitchLocal.json"

    static func runIfRequested(using library: DocumentLibraryController) async {
        if ProcessInfo.processInfo.arguments.contains(switchLocalArgument) {
            await switchToLocal(using: library)
            return
        }
        if let token = requestedToken(after: offlineArgument) {
            await runOfflineRead(using: library, token: token)
            return
        }
        guard let token = requestedToken(after: argument) else { return }

        let result: ResultPayload
        do {
            guard library.storageMode == .iCloud else {
                throw SmokeError.cloudModeNotActive
            }
            guard case .cloudReady = library.state else {
                throw SmokeError.cloudRuntimeNotReady(String(describing: library.state))
            }
            guard library.activeRootURL.standardizedFileURL != library.localRootURL.standardizedFileURL else {
                throw SmokeError.cloudRootMatchesLocalRoot
            }

            let folder = try await library.createFolder(
                named: "Hashmark S4.6 Smoke \(token)",
                in: library.activeRootURL
            )
            let document = try await library.createMarkdown(named: "Round Trip", in: folder)
            let expected = "# Hashmark S4.6\n\nReal iCloud container token: \(token)\n"
            try await library.writeText(expected, to: document)
            let actual = try await library.readText(at: document)
            guard actual == expected else { throw SmokeError.roundTripMismatch }

            let children = try await library.contents(of: folder)
            guard children.contains(where: { $0.url.standardizedFileURL == document.standardizedFileURL }) else {
                throw SmokeError.documentMissingFromCoordinatedListing
            }

            // Allow presenter notifications caused by our own writes to settle before
            // waiting for the Mac/Files-side edit identified by this exact token.
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let externalMarker = "External edit token: \(token)"
            var observedRevision = library.revision
            let deadline = Date().addingTimeInterval(30)
            var externalChangeObserved = false
            while Date() < deadline {
                try Task.checkCancellation()
                if library.revision != observedRevision {
                    observedRevision = library.revision
                    let externallyEdited = try await library.readText(at: document)
                    if externallyEdited.contains(externalMarker) {
                        externalChangeObserved = true
                        break
                    }
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard externalChangeObserved else {
                throw SmokeError.externalChangeNotObserved
            }

            result = ResultPayload(
                success: true,
                token: token,
                cloudRootPath: library.activeRootURL.path,
                testFolderName: folder.lastPathComponent,
                testDocumentName: document.lastPathComponent,
                roundTripBytes: expected.utf8.count,
                externalChangeObserved: true,
                offlineReadPassed: false,
                message: "Real iCloud create/write/read/list and external presenter refresh passed; fixture retained for Files verification."
            )
        } catch {
            result = ResultPayload(
                success: false,
                token: token,
                cloudRootPath: library.activeRootURL.path,
                testFolderName: nil,
                testDocumentName: nil,
                roundTripBytes: 0,
                externalChangeObserved: false,
                offlineReadPassed: false,
                message: error.localizedDescription
            )
        }

        persist(result)
        print("HASHMARK_S46_SMOKE=\(result.success ? "PASS" : "FAIL") token=\(token) message=\(result.message)")
    }

    private static func switchToLocal(using library: DocumentLibraryController) async {
        let result: SwitchLocalResult
        do {
            if library.storageMode == .iCloud {
                try await library.disableICloud()
            }
            guard library.storageMode == .local,
                  library.activeRootURL.standardizedFileURL == library.localRootURL.standardizedFileURL else {
                throw SmokeError.localModeNotCommitted
            }
            let localItems = try await library.contents(of: library.localRootURL)
            result = SwitchLocalResult(
                success: true,
                storageMode: library.storageMode.rawValue,
                activeRootPath: library.activeRootURL.path,
                localVisibleItemCount: localItems.count,
                message: "The transactional iCloud disable completed and retained the cloud library."
            )
        } catch {
            result = SwitchLocalResult(
                success: false,
                storageMode: library.storageMode.rawValue,
                activeRootPath: library.activeRootURL.path,
                localVisibleItemCount: 0,
                message: error.localizedDescription
            )
        }
        persistSwitchLocal(result)
        print("HASHMARK_SWITCH_LOCAL=\(result.success ? "PASS" : "FAIL") mode=\(result.storageMode) message=\(result.message)")
    }

    private static func runOfflineRead(using library: DocumentLibraryController, token: String) async {
        let folder = library.activeRootURL.appendingPathComponent(
            "Hashmark S4.6 Smoke \(token)",
            isDirectory: true
        )
        let document = folder.appendingPathComponent("Round Trip.md")
        let result: ResultPayload
        do {
            guard library.storageMode == .iCloud else {
                throw SmokeError.cloudModeNotActive
            }
            let text = try await library.readText(at: document)
            guard text.contains("Real iCloud container token: \(token)"),
                  text.contains("External edit token: \(token)") else {
                throw SmokeError.offlineFixtureMismatch
            }
            result = ResultPayload(
                success: true,
                token: token,
                cloudRootPath: library.activeRootURL.path,
                testFolderName: folder.lastPathComponent,
                testDocumentName: document.lastPathComponent,
                roundTripBytes: text.utf8.count,
                externalChangeObserved: false,
                offlineReadPassed: true,
                message: "Previously downloaded iCloud fixture was readable through the app cloud path."
            )
        } catch {
            result = ResultPayload(
                success: false,
                token: token,
                cloudRootPath: library.activeRootURL.path,
                testFolderName: folder.lastPathComponent,
                testDocumentName: document.lastPathComponent,
                roundTripBytes: 0,
                externalChangeObserved: false,
                offlineReadPassed: false,
                message: error.localizedDescription
            )
        }
        persist(result)
        print("HASHMARK_S46_OFFLINE_SMOKE=\(result.success ? "PASS" : "FAIL") token=\(token) message=\(result.message)")
    }

    private static func requestedToken(after argument: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else {
            return nil
        }
        let token = arguments[index + 1]
        let allowed = token.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0)
        }
        return allowed && !token.isEmpty ? token : nil
    }

    private static func persist(_ result: ResultPayload) {
        do {
            let caches = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let data = try JSONEncoder.prettyPrinted.encode(result)
            try data.write(to: caches.appendingPathComponent(resultFilename), options: .atomic)
        } catch {
            print("HASHMARK_S46_SMOKE_RESULT_WRITE_FAILED=\(error.localizedDescription)")
        }
    }

    private static func persistSwitchLocal(_ result: SwitchLocalResult) {
        do {
            let caches = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let data = try JSONEncoder.prettyPrinted.encode(result)
            try data.write(to: caches.appendingPathComponent(switchLocalResultFilename), options: .atomic)
        } catch {
            print("HASHMARK_SWITCH_LOCAL_RESULT_WRITE_FAILED=\(error.localizedDescription)")
        }
    }
}

private extension ICloudDeviceSmokeRunner {
    struct ResultPayload: Codable {
        let success: Bool
        let token: String
        let cloudRootPath: String
        let testFolderName: String?
        let testDocumentName: String?
        let roundTripBytes: Int
        let externalChangeObserved: Bool
        let offlineReadPassed: Bool
        let message: String
    }

    struct SwitchLocalResult: Codable {
        let success: Bool
        let storageMode: String
        let activeRootPath: String
        let localVisibleItemCount: Int
        let message: String
    }

    enum SmokeError: LocalizedError {
        case cloudModeNotActive
        case cloudRuntimeNotReady(String)
        case cloudRootMatchesLocalRoot
        case roundTripMismatch
        case documentMissingFromCoordinatedListing
        case externalChangeNotObserved
        case offlineFixtureMismatch
        case localModeNotCommitted

        var errorDescription: String? {
            switch self {
            case .cloudModeNotActive:
                return "The Debug launch did not activate iCloud mode."
            case .cloudRuntimeNotReady(let state):
                return "The real iCloud runtime is not ready: \(state)"
            case .cloudRootMatchesLocalRoot:
                return "The resolved cloud root unexpectedly matches the local Documents root."
            case .roundTripMismatch:
                return "The coordinated iCloud read did not match the bytes that were written."
            case .documentMissingFromCoordinatedListing:
                return "The test document was absent from the coordinated cloud listing."
            case .externalChangeNotObserved:
                return "The app did not observe the tokened external iCloud edit within 30 seconds."
            case .offlineFixtureMismatch:
                return "The downloaded iCloud fixture did not contain both expected test markers."
            case .localModeNotCommitted:
                return "The transactional disable did not commit local mode."
            }
        }
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
#endif
