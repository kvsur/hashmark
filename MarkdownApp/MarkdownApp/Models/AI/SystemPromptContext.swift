//
//  SystemPromptContext.swift
//  MarkdownApp
//
//  Dynamic system context added immediately before each network request.
//

import Foundation

nonisolated enum SystemPromptContext {
    private static let dateTimePrefix = "Current local date and time: "

    static func injectingCurrentDateTime(
        into messages: [AIMessage],
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> [AIMessage] {
        let history = messages.filter { !isInjectedDateTimeMessage($0) }
        return [
            AIMessage(
                role: .system,
                content: currentDateTimeLine(now: now, timeZone: timeZone)
            )
        ] + history
    }

    static func currentDateTimeLine(now: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return dateTimePrefix + formatter.string(from: now)
    }

    private static func isInjectedDateTimeMessage(_ message: AIMessage) -> Bool {
        guard message.role == .system, message.content.hasPrefix(dateTimePrefix) else {
            return false
        }
        let value = String(message.content.dropFirst(dateTimePrefix.count))
        return value.range(
            of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#,
            options: .regularExpression
        ) != nil
    }
}
