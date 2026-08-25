//
//  AITool.swift
//  MarkdownApp
//
//  Function tool calling 的中立模型层：工具定义（AITool），以及本 App 唯一的业务工具
//  「反问澄清」（ClarifyTool + 解析出的 ClarifyRequest）。流式事件独立在 AIStreamEvent.swift。
//  工具入参 schema 用 JSONValue 表达；每家 Adapter 再映射到自己的第一方工具定义。
//

import Foundation

// MARK: - 任意 JSON 值（用于编码工具的 JSON Schema）

/// 可编码的任意 JSON 值。用 Swift 字面量搭出 JSON Schema，再交给 Provider Adapter。
nonisolated indirect enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// 递归把 JSONSerialization 的 Foundation 对象转为 JSONValue。
    nonisolated static func foundation(_ any: Any) -> JSONValue {
        switch any {
        case let dict as [String: Any]:
            .object(dict.mapValues(JSONValue.foundation))
        case let array as [Any]:
            .array(array.map(JSONValue.foundation))
        case let string as String:
            .string(string)
        case let bool as Bool:
            .bool(bool)
        case let number as NSNumber:
            .number(number.doubleValue)
        default:
            .null
        }
    }
}

nonisolated extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    func string(for key: String) -> String? {
        guard case .string(let value)? = objectValue?[key] else { return nil }
        return value
    }
}

// MARK: - 工具定义

/// 一个可供模型调用的工具（供应商无关）。parameters 是 JSON Schema（object）。
nonisolated struct AITool {
    let name: String
    let description: String
    let parameters: JSONValue
}

// MARK: - 反问澄清工具

/// 本 App 提供给模型的唯一工具：诉求含糊时反问用户以挖掘诉求。
/// 一次只问一个问题；回答方式为 单选/多选/文字，选择型带候选项与推荐项。
///
/// 工具描述同样是 prompt，故与 AIAction 一致用英文写。
/// definition 是计算属性而非常量：问题与候选项必须用**当前界面语言**书写
/// （它们是说给用户听的界面文本，不同于正文跟随文档语言——见 AIPromptLocale 的双语义说明），
/// 而界面语言可在运行时切换，描述需随之重新生成。
enum ClarifyTool {
    static let name = "ask_clarifying_question"

    static var definition: AITool {
        let uiLanguage = AIPromptLocale.uiLanguageName
        return AITool(
            name: name,
            description: """
            When the user's writing request is vague or missing key information (topic scope, target reader, \
            length, tone, points that must be covered, and so on), call this tool to ask the user one \
            clarifying question instead of guessing and generating anyway. Ask only the single most important \
            question. If you already have enough information, start writing and do not call this tool.

            The question and every option label MUST be written in \(uiLanguage). They are shown in the app's \
            interface and are what the user reads, so they follow the interface language — which is \
            independent of the language of the document being written.
            """,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "question": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The clarifying question to ask the user. Concise, specific, one thing at a time. "
                                + "Must be written in \(uiLanguage)."
                        )
                    ]),
                    "answer_type": .object([
                        "type": .string("string"),
                        "enum": .array([.string("single_select"), .string("multi_select"), .string("text")]),
                        "description": .string(
                            "How the user should answer: single_select, multi_select, or text (free input)."
                        )
                    ]),
                    "options": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Provide more than 2 options when answer_type is single_select or multi_select; "
                                + "omit for text."
                        ),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "label": .object([
                                    "type": .string("string"),
                                    "description": .string("Option text, written in \(uiLanguage).")
                                ]),
                                "recommended": .object([
                                    "type": .string("boolean"),
                                    "description": .string(
                                        "Whether this is the recommended option; mark at most one."
                                    )
                                ])
                            ]),
                            "required": .array([.string("label")])
                        ])
                    ])
                ]),
                "required": .array([.string("question"), .string("answer_type")])
            ])
        )
    }
}

/// 从工具调用 arguments 解析出的、可供 UI 直接渲染的反问请求。
struct ClarifyRequest: Equatable {
    let question: String
    let answerSpec: AnswerSpec

    struct Option: Equatable, Identifiable {
        let label: String
        let recommended: Bool
        var id: String { label }
    }

    enum AnswerSpec: Equatable {
        case singleSelect([Option])
        case multiSelect([Option])
        case text
    }

    /// 从工具调用的 arguments（JSON 字符串）解析。
    /// 任一关键字段缺失/非法（含选择型无候选项）返回 nil——上层据此降级为直接生成，不阻断。
    init?(argumentsJSON: String) {
        guard let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawQuestion = obj["question"] as? String,
              case let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines),
              !question.isEmpty,
              let type = obj["answer_type"] as? String
        else { return nil }

        self.question = question

        let rawOptions = obj["options"] as? [[String: Any]] ?? []
        let options: [Option] = rawOptions.compactMap { dict in
            guard let label = (dict["label"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty
            else { return nil }
            return Option(label: label, recommended: dict["recommended"] as? Bool ?? false)
        }

        switch type {
        case "single_select":
            guard !options.isEmpty else { return nil }
            answerSpec = .singleSelect(options)
        case "multi_select":
            guard !options.isEmpty else { return nil }
            answerSpec = .multiSelect(options)
        case "text":
            answerSpec = .text
        default:
            return nil
        }
    }
}
