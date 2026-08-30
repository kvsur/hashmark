import Foundation

@main
enum DocumentReleaseQATests {
    static func main() async throws {
        try await testFreshInstallAndEmptyLibraryRoundTrip()
        try await testNestedLargeLibraryUpgrade()
        try await testEnableTerminationAtEveryCheckpoint()
        try await testDisableTerminationAtEveryCheckpoint()
        try await testStorageQuotaAndCleanupFailures()
        try await testAccountLogoutChangeAndRetry()
        print("DocumentReleaseQATests: PASS")
    }

    @MainActor
    private static func testFreshInstallAndEmptyLibraryRoundTrip() async throws {
        try await withReleaseQAFixture { fixture in
            let controller = fixture.makeController()
            try await controller.enableICloud()
            releaseQAExpect(controller.storageMode == .iCloud, "an empty fresh install must enable iCloud")
            releaseQAExpect(releaseQAMarkdownURLs(in: fixture.cloudDocumentsURL).isEmpty, "empty migration must not invent files")

            try await controller.disableICloud()
            releaseQAExpect(controller.storageMode == .local, "an empty cloud library must disable safely")
            releaseQAExpect(FileManager.default.fileExists(atPath: fixture.cloudDocumentsURL.path), "disable must retain the cloud container")

            try await controller.enableICloud()
            releaseQAExpect(controller.storageMode == .iCloud, "an empty library must re-enable idempotently")
        }
    }

    @MainActor
    private static func testNestedLargeLibraryUpgrade() async throws {
        try await withReleaseQAFixture { fixture in
            let expectedCount = 500
            for folderIndex in 0..<25 {
                for fileIndex in 0..<20 {
                    let relative = "Folder \(folderIndex)/Document \(fileIndex).md"
                    try releaseQAWrite("payload-\(folderIndex)-\(fileIndex)", to: fixture.localRootURL.appendingPathComponent(relative))
                }
            }
            var deep = fixture.localRootURL
            for level in 0..<20 { deep.appendPathComponent("Depth \(level)", isDirectory: true) }
            try FileManager.default.createDirectory(at: deep.appendingPathComponent("Empty", isDirectory: true), withIntermediateDirectories: true)
            try releaseQAWrite("deep-payload", to: deep.appendingPathComponent("Deep.md"))
            try releaseQAWrite("staged", to: fixture.inboxURL.appendingPathComponent("Staged.md"))

            let started = ContinuousClock.now
            let controller = fixture.makeController()
            try await controller.enableICloud()
            let elapsed = started.duration(to: .now)

            releaseQAExpect(controller.storageMode == .iCloud, "large nested upgrade must commit cloud mode")
            releaseQAExpect(releaseQAMarkdownURLs(in: fixture.cloudDocumentsURL).count == expectedCount + 1, "large upgrade must preserve every Markdown document")
            try releaseQAExpect(releaseQARead(fixture.cloudDocumentsURL.appendingPathComponent("Folder 24/Document 19.md")) == "payload-24-19", "large upgrade must preserve bytes")
            let cloudDeepEmpty = fixture.cloudDocumentsURL.appendingPathComponent(
                deep.path.replacingOccurrences(of: fixture.localRootURL.path + "/", with: "") + "/Empty",
                isDirectory: true
            )
            releaseQAExpect(FileManager.default.fileExists(atPath: cloudDeepEmpty.path), "deep empty folders must survive migration")
            releaseQAExpect(FileManager.default.fileExists(atPath: fixture.inboxURL.appendingPathComponent("Staged.md").path), "Inbox must remain local staging")
            releaseQAExpect(elapsed < .seconds(30), "501-document migration exceeded the 30-second release budget")
        }
    }

    @MainActor
    private static func testEnableTerminationAtEveryCheckpoint() async throws {
        let points: [DocumentMigrationFaultPoint] = [
            .crashAfterPrepared,
            .crashAfterRecoveryBackup,
            .crashAfterMerge,
            .crashAfterVerification,
            .crashBeforeModeCommit,
            .crashAfterModeCommit,
            .crashAfterCleanup
        ]
        for point in points {
            try await withReleaseQAFixture(faults: ReleaseQAFaults(point)) { fixture in
                let source = fixture.localRootURL.appendingPathComponent("Enable-\(point.rawValue).md")
                try releaseQAWrite("enable-\(point.rawValue)", to: source)
                let controller = fixture.makeController()
                do {
                    try await controller.enableICloud()
                    throw ReleaseQATestError("enable did not stop at \(point.rawValue)")
                } catch let error as ReleaseQAError {
                    releaseQAExpect(error == .crash(point), "enable must surface the exact checkpoint")
                }

                let restarted = fixture.makeController()
                await restarted.start()
                if restarted.storageMode == .local { try await restarted.enableICloud() }
                releaseQAExpect(restarted.storageMode == .iCloud, "enable restart must settle cloud mode after \(point.rawValue)")
                let cloudURL = fixture.cloudDocumentsURL.appendingPathComponent(source.lastPathComponent)
                try releaseQAExpect(releaseQARead(cloudURL) == "enable-\(point.rawValue)", "enable restart lost bytes after \(point.rawValue)")
                let journal = try await fixture.migrationService.loadJournal()
                releaseQAExpect(journal?.checkpoint == .cleanupCompleted, "enable restart must finish cleanup after \(point.rawValue)")
            }
        }
    }

    @MainActor
    private static func testDisableTerminationAtEveryCheckpoint() async throws {
        let points: [DocumentMigrationFaultPoint] = [
            .crashAfterPrepared,
            .crashAfterRecoveryBackup,
            .crashAfterMerge,
            .crashAfterVerification,
            .crashBeforeModeCommit,
            .crashAfterModeCommit,
            .crashAfterCleanup
        ]
        for point in points {
            try await withReleaseQAFixture(faults: ReleaseQAFaults(point)) { fixture in
                let cloudURL = fixture.cloudDocumentsURL.appendingPathComponent("Disable-\(point.rawValue).md")
                try releaseQAWrite("disable-\(point.rawValue)", to: cloudURL)
                fixture.preferences.saveMode(.iCloud)
                let controller = fixture.makeController()
                await controller.start()
                do {
                    try await controller.disableICloud()
                    throw ReleaseQATestError("disable did not stop at \(point.rawValue)")
                } catch let error as ReleaseQAError {
                    releaseQAExpect(error == .crash(point), "disable must surface the exact checkpoint")
                }

                let restarted = fixture.makeController()
                await restarted.start()
                if restarted.storageMode == .iCloud { try await restarted.disableICloud() }
                releaseQAExpect(restarted.storageMode == .local, "disable restart must settle local mode after \(point.rawValue)")
                let localURL = fixture.localRootURL.appendingPathComponent(cloudURL.lastPathComponent)
                try releaseQAExpect(releaseQARead(localURL) == "disable-\(point.rawValue)", "disable restart lost local bytes after \(point.rawValue)")
                try releaseQAExpect(releaseQARead(cloudURL) == "disable-\(point.rawValue)", "disable restart deleted cloud bytes after \(point.rawValue)")
                let journal = try await fixture.migrationService.loadJournal()
                releaseQAExpect(journal?.checkpoint == .cleanupCompleted, "disable restart must finish after \(point.rawValue)")
            }
        }
    }

    @MainActor
    private static func testStorageQuotaAndCleanupFailures() async throws {
        try await withReleaseQAFixture(faults: ReleaseQAFaults(.copy, error: .diskFull)) { fixture in
            let source = fixture.localRootURL.appendingPathComponent("Disk Full.md")
            try releaseQAWrite("only-local-copy", to: source)
            let controller = fixture.makeController()
            do { try await controller.enableICloud(); throw ReleaseQATestError("disk-full injection did not fail") }
            catch let error as ReleaseQAError { releaseQAExpect(error == .diskFull, "disk-full identity was lost") }
            releaseQAExpect(controller.storageMode == .local && FileManager.default.fileExists(atPath: source.path), "disk-full must keep committed local bytes")
            try await controller.enableICloud()
            releaseQAExpect(controller.storageMode == .iCloud, "disk-full retry must resume safely")
        }

        try await withReleaseQAFixture(faults: ReleaseQAFaults(.download, error: .quotaExceeded)) { fixture in
            let cloudURL = fixture.cloudDocumentsURL.appendingPathComponent("Quota.md")
            try releaseQAWrite("only-cloud-copy", to: cloudURL)
            fixture.preferences.saveMode(.iCloud)
            let controller = fixture.makeController()
            await controller.start()
            do { try await controller.disableICloud(); throw ReleaseQATestError("quota injection did not fail") }
            catch let error as ReleaseQAError { releaseQAExpect(error == .quotaExceeded, "quota identity was lost") }
            releaseQAExpect(controller.storageMode == .iCloud && FileManager.default.fileExists(atPath: cloudURL.path), "quota failure must keep committed cloud bytes")
            try await controller.disableICloud()
            releaseQAExpect(controller.storageMode == .local, "quota retry must resume safely")
        }

        try await withReleaseQAFixture(faults: ReleaseQAFaults(.delete, error: .diskFull)) { fixture in
            let source = fixture.localRootURL.appendingPathComponent("Cleanup Debt.md")
            try releaseQAWrite("verified-cloud-copy", to: source)
            let controller = fixture.makeController()
            try await controller.enableICloud()
            guard case .failed = controller.state else { fatalError("cleanup failure must expose retained debt") }
            releaseQAExpect(controller.storageMode == .iCloud && FileManager.default.fileExists(atPath: source.path), "cleanup debt may retain source only after cloud commit")
            let restarted = fixture.makeController()
            await restarted.start()
            releaseQAExpect(!FileManager.default.fileExists(atPath: source.path), "launch retry must clear recoverable cleanup debt")
        }
    }

    @MainActor
    private static func testAccountLogoutChangeAndRetry() async throws {
        try await withReleaseQAFixture { fixture in
            fixture.preferences.saveMode(.iCloud)
            let controller = fixture.makeController()
            await controller.start()
            fixture.cloudRuntime.update(containerURL: nil, identity: nil)
            NotificationCenter.default.post(name: NSNotification.Name.NSUbiquityIdentityDidChange, object: nil)
            try await Task.sleep(nanoseconds: 100_000_000)
            releaseQAExpect(controller.storageMode == .iCloud, "account logout must not switch to local")
            guard case .cloudUnavailable = controller.state else { fatalError("account logout must freeze cloud access") }
            do {
                _ = try await controller.createMarkdown(named: "Blocked", in: controller.activeRootURL)
                fatalError("account logout must freeze mutations")
            } catch DocumentLibraryError.mutationsFrozen {}

            fixture.cloudRuntime.update(containerURL: fixture.cloudContainerURL, identity: "replacement-account")
            await controller.retryICloudAccess()
            releaseQAExpect(controller.storageMode == .iCloud && controller.state == .cloudReady, "retry must re-resolve the replacement account without local fallback")
            _ = try await controller.createMarkdown(named: "Recovered", in: controller.activeRootURL)
        }
    }
}
