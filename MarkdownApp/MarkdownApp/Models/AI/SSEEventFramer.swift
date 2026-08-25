//
//  SSEEventFramer.swift
//  MarkdownApp
//
//  Provider-neutral SSE data framing shared by every streaming adapter.
//

import Foundation

nonisolated enum SSEFrame {
    case data(Data)
    case done
}

nonisolated struct SSEEventFramer {
    private var dataLines: [String] = []

    mutating func receive(line: String) -> [SSEFrame] {
        let line = line.trimmingCharacters(in: .newlines)
        if line.isEmpty { return flush() }

        guard line.hasPrefix("data:") else { return [] }
        var value = String(line.dropFirst(5))
        if value.hasPrefix(" ") { value.removeFirst() }

        // Empty data frames are commonly used as transport heartbeats.
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        if value.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            return flush() + [.done]
        }

        dataLines.append(value)

        // Some providers or URLSession.AsyncBytes.lines do not surface an empty
        // separator between complete data records. Emit as soon as the buffered
        // payload is valid JSON, while still supporting genuine multi-line JSON.
        return bufferedPayloadIsCompleteJSON ? flush() : []
    }

    mutating func finish() -> [SSEFrame] {
        flush()
    }

    private var bufferedPayloadIsCompleteJSON: Bool {
        guard let data = payloadData() else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    private mutating func flush() -> [SSEFrame] {
        defer { dataLines.removeAll(keepingCapacity: true) }
        guard let data = payloadData() else { return [] }
        return [.data(data)]
    }

    private func payloadData() -> Data? {
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return payload.data(using: .utf8)
    }
}
