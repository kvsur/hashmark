//
//  AITool.swift
//  MarkdownApp
//
//  Function tool calling 的中立模型层：工具定义（AITool）、流式事件（AIStreamEvent）、
//  以及本 App 唯一的业务工具「反问澄清」（ClarifyTool + 解析出的 ClarifyRequest）。
//  工具的入参 schema 用 JSONValue 表达——它同时能编码成 OpenAI 的 parameters 与
//  Anthropic 的 input_schema（两者都是 JSON Schema），一份定义两处复用（DRY）。
//

import Foundation

// MARK: - 任意 JSON 值（用于编码工具的 JSON Schema）

/// 可编码的任意 JSON 值。让我们用 Swift 字面量搭出 JSON Schema，再交给两种上游各自的请求体。
indirect enum JSONValue: Encodable {
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
}

// MARK: - 工具定义与流式事件

/// 一个可供模型调用的工具（供应商无关）。parameters 是 JSON Schema（object）。
struct AITool {
    let name: String
    let description: String
    let parameters: JSONValue
}

/// 流式产出的事件：正文文本增量，或一次完整的工具调用。
/// 关键约束：只有 .text 进正文渲染区；.toolCall 交给会话层处理，绝不渲染成正文。
enum AIStreamEvent {
    case text(String)
    case toolCall(AIToolCall)
}

// MARK: - 反问澄清工具

/// 本 App 提供给模型的唯一工具：诉求含糊时反问用户以挖掘诉求。
/// 一次只问一个问题；回答方式为 单选/多选/文字，选择型带候选项与推荐项。
enum ClarifyTool {
    static let name = "ask_clarifying_question"

    static var definition: AITool {
        AITool(
            name: name,
            description: """
            当用户的写作诉求含糊、缺少关键信息（如主题范围、目标读者、篇幅、语气、必须包含的要点等）时，
            调用本工具向用户提出一个澄清问题，而不是凭空猜测就生成。一次只问最关键的一个问题；
            若信息已足够，请直接开始写作，不要调用本工具。
            """,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "question": .object([
                        "type": .string("string"),
                        "description": .string("要向用户提出的澄清问题，简洁、具体、一次只问一件事。")
                    ]),
                    "answer_type": .object([
                        "type": .string("string"),
                        "enum": .array([.string("single_select"), .string("multi_select"), .string("text")]),
                        "description": .string("期望的回答方式：single_select 单选、multi_select 多选、text 自由文字。")
                    ]),
                    "options": .object([
                        "type": .string("array"),
                        "description": .string("当 answer_type 为 single_select 或 multi_select 时提供 2 个以上候选项；text 时省略。"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "label": .object([
                                    "type": .string("string"),
                                    "description": .string("候选项文案")
                                ]),
                                "recommended": .object([
                                    "type": .string("boolean"),
                                    "description": .string("是否为推荐项；最多标记一个推荐项")
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
