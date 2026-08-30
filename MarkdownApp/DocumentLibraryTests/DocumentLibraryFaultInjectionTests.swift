import Foundation

/// Stable seam names used by the iCloud runtime and migration tests in later steps.
enum DocumentLibraryFaultPoint: String, CaseIterable {
    case containerResolution
    case download
    case copy
    case write
    case delete
    case crashBeforeModeCommit
    case crashAfterModeCommit
    case externalChange
    case versionConflict
}

struct DocumentLibraryFault: Error, Equatable {
    let point: DocumentLibraryFaultPoint
}

struct DocumentLibraryFaultInjector {
    private var remainingFailures: [DocumentLibraryFaultPoint: Int]

    init(failOnceAt points: Set<DocumentLibraryFaultPoint>) {
        remainingFailures = Dictionary(uniqueKeysWithValues: points.map { ($0, 1) })
    }

    mutating func checkpoint(_ point: DocumentLibraryFaultPoint) throws {
        guard let remaining = remainingFailures[point], remaining > 0 else { return }
        remainingFailures[point] = remaining - 1
        throw DocumentLibraryFault(point: point)
    }
}

@main
enum DocumentLibraryFaultInjectionTests {
    static func main() throws {
        try testEveryDeclaredSeamFailsDeterministicallyAndCanRetry()
        testScenarioContractIsComplete()
        print("DocumentLibraryFaultInjectionTests: PASS")
    }

    private static func testEveryDeclaredSeamFailsDeterministicallyAndCanRetry() throws {
        for point in DocumentLibraryFaultPoint.allCases {
            var injector = DocumentLibraryFaultInjector(failOnceAt: [point])
            do {
                try injector.checkpoint(point)
                fatalError("\(point.rawValue) should fail on its armed invocation")
            } catch let fault as DocumentLibraryFault {
                expect(fault.point == point, "fault should retain the exact seam identity")
            }
            try injector.checkpoint(point)
        }
    }

    private static func testScenarioContractIsComplete() {
        let invariants: [DocumentLibraryFaultPoint: String] = [
            .containerResolution: "keep the committed mode and expose retry",
            .download: "retain the only cloud copy and do not commit local mode",
            .copy: "retain source bytes and resume from the journal",
            .write: "leave the previous destination intact through atomic replacement",
            .delete: "report cleanup debt without deleting another sole copy",
            .crashBeforeModeCommit: "resume or roll back while preserving the old mode",
            .crashAfterModeCommit: "use the new mode and finish idempotent cleanup",
            .externalChange: "refresh clean consumers without discarding dirty drafts",
            .versionConflict: "materialize every distinct version before resolution"
        ]
        expect(Set(invariants.keys) == Set(DocumentLibraryFaultPoint.allCases),
               "every fault seam must carry an explicit no-data-loss invariant")
        expect(invariants.values.allSatisfy { !$0.isEmpty }, "fault invariants must be actionable")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
