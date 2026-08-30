import Foundation

nonisolated protocol FileAccessCoordinating: Sendable {
    func read<T>(at url: URL, accessor: (URL) throws -> T) throws -> T
    func write<T>(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        accessor: (URL) throws -> T
    ) throws -> T
    func readWrite<T>(
        reading sourceURL: URL,
        writing destinationURL: URL,
        accessor: (URL, URL) throws -> T
    ) throws -> T
    func move<T>(
        from sourceURL: URL,
        to destinationURL: URL,
        accessor: (URL, URL) throws -> T
    ) throws -> T
}

nonisolated struct DirectFileAccessCoordinator: FileAccessCoordinating {
    func read<T>(at url: URL, accessor: (URL) throws -> T) throws -> T {
        try accessor(url)
    }

    func write<T>(
        at url: URL,
        options: NSFileCoordinator.WritingOptions = [],
        accessor: (URL) throws -> T
    ) throws -> T {
        try accessor(url)
    }

    func readWrite<T>(
        reading sourceURL: URL,
        writing destinationURL: URL,
        accessor: (URL, URL) throws -> T
    ) throws -> T {
        try accessor(sourceURL, destinationURL)
    }

    func move<T>(
        from sourceURL: URL,
        to destinationURL: URL,
        accessor: (URL, URL) throws -> T
    ) throws -> T {
        try accessor(sourceURL, destinationURL)
    }
}

/// iCloud-backed stores use this implementation so reads and mutations participate in
/// file-presenter arbitration. Local mode keeps the direct implementation for lower overhead.
nonisolated final class CoordinatedFileAccessCoordinator: FileAccessCoordinating, @unchecked Sendable {
    private let coordinator: NSFileCoordinator

    init(filePresenter: NSFilePresenter? = nil) {
        coordinator = NSFileCoordinator(filePresenter: filePresenter)
    }

    func read<T>(at url: URL, accessor: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try accessor(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    func write<T>(
        at url: URL,
        options: NSFileCoordinator.WritingOptions = [],
        accessor: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            result = Result { try accessor(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    func readWrite<T>(
        reading sourceURL: URL,
        writing destinationURL: URL,
        accessor: (URL, URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [],
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedSource, coordinatedDestination in
            result = Result { try accessor(coordinatedSource, coordinatedDestination) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    func move<T>(
        from sourceURL: URL,
        to destinationURL: URL,
        accessor: (URL, URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedSource, coordinatedDestination in
            result = Result { try accessor(coordinatedSource, coordinatedDestination) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }
}
