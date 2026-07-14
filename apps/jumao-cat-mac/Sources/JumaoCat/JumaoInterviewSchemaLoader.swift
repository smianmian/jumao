import Foundation

enum ProjectInterviewMode: String, Equatable, Sendable {
  case newProject
  case existingProject
}

struct JumaoInterviewSchema: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let stages: [JumaoInterviewStage]
  let questions: [JumaoInterviewQuestion]

  init(
    schemaVersion: Int,
    stages: [JumaoInterviewStage] = [Self.legacyStage],
    questions: [JumaoInterviewQuestion]
  ) {
    self.schemaVersion = schemaVersion
    self.stages = stages
    self.questions = questions
  }

  static let legacyStage = JumaoInterviewStage(
    id: "legacy",
    title: "回答项目问题",
    description: "按顺序回答项目问题。",
    order: 1
  )

  func focused(for mode: ProjectInterviewMode) -> JumaoInterviewSchema {
    let stage = JumaoInterviewStage(
      id: "intake",
      title: mode == .newProject ? "规划新项目" : "梳理这次改动",
      description: mode == .newProject
        ? "先回答四个最重要的问题。"
        : "扫描结果已经确认的内容不会重复询问。",
      order: 1
    )

    let questions: [JumaoInterviewQuestion]
    switch mode {
    case .newProject:
      questions = [
        focusedQuestion(
          id: "projectSummary",
          answerPath: "newProject.projectSummary",
          title: "你想做一个什么项目？",
          description: "用自己的话说清楚这个项目要解决什么问题。",
          placeholder: "例如：一个帮助我整理客户跟进记录的工具",
          order: 1
        ),
        focusedQuestion(
          id: "coreFeatures",
          answerPath: "newProject.coreFeatures",
          title: "最核心的功能有哪些？",
          description: "只列第一版不能缺少的功能。",
          placeholder: "例如：记录客户，设置提醒，查看跟进状态",
          inputType: "list",
          order: 2
        ),
        focusedQuestion(
          id: "primaryGoal",
          answerPath: "newProject.primaryGoal",
          title: "当前最重要的目标是什么？",
          description: "先确定这一版最需要达成的结果。",
          placeholder: "例如：先让自己每天能稳定完成客户跟进",
          order: 3
        ),
        focusedQuestion(
          id: "targetPlatform",
          answerPath: "newProject.targetPlatform",
          title: "准备运行在哪个平台？",
          description: "填写第一版准备使用的平台。",
          placeholder: "例如：macOS、iPhone、网页",
          order: 4
        )
      ]
    case .existingProject:
      questions = [
        focusedQuestion(
          id: "requestedChange",
          answerPath: "existingProject.requestedChange",
          title: "这次准备修改什么？",
          description: "只说明这一次要新增、调整或修复的内容。",
          placeholder: "例如：修复导入项目后入口按钮无反应",
          order: 1
        ),
        focusedQuestion(
          id: "currentBlockers",
          answerPath: "existingProject.currentBlockers",
          title: "当前遇到了什么问题或阻塞？",
          description: "说明现在看见的现象，或导致无法继续的原因。",
          placeholder: "例如：点击后没有打开任何窗口",
          order: 2
        ),
        focusedQuestion(
          id: "protectedFeatures",
          answerPath: "existingProject.protectedFeatures",
          title: "哪些现有功能绝对不能被破坏？",
          description: "列出本次修改必须保持正常的功能。",
          placeholder: "例如：项目扫描，草稿恢复，任务包生成",
          inputType: "list",
          order: 3
        )
      ]
    }

    return JumaoInterviewSchema(schemaVersion: schemaVersion, stages: [stage], questions: questions)
  }

  private func focusedQuestion(
    id: String,
    answerPath: String,
    title: String,
    description: String,
    placeholder: String,
    inputType: String = "text",
    order: Int
  ) -> JumaoInterviewQuestion {
    JumaoInterviewQuestion(
      id: id,
      answerPath: answerPath,
      title: title,
      description: description,
      placeholder: placeholder,
      stage: "intake",
      inputType: inputType,
      required: true,
      order: order
    )
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion, stages, questions
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    stages = try container.decodeIfPresent([JumaoInterviewStage].self, forKey: .stages) ?? [Self.legacyStage]
    questions = try container.decode([JumaoInterviewQuestion].self, forKey: .questions)
  }
}

struct JumaoInterviewStage: Codable, Equatable, Sendable {
  let id: String
  let title: String
  let description: String
  let order: Int
}

struct JumaoInterviewQuestion: Codable, Equatable, Sendable {
  let id: String
  let answerPath: String
  let title: String
  let description: String
  let guidance: String?
  let example: String?
  let placeholder: String?
  let stage: String?
  let inputType: String
  let required: Bool
  let order: Int

  init(
    id: String,
    answerPath: String,
    title: String,
    description: String,
    guidance: String? = nil,
    example: String? = nil,
    placeholder: String? = nil,
    stage: String? = nil,
    inputType: String,
    required: Bool,
    order: Int
  ) {
    self.id = id
    self.answerPath = answerPath
    self.title = title
    self.description = description
    self.guidance = guidance
    self.example = example
    self.placeholder = placeholder
    self.stage = stage
    self.inputType = inputType
    self.required = required
    self.order = order
  }

  enum CodingKeys: String, CodingKey {
    case id, answerPath, title, description, guidance, example, placeholder, stage, inputType, required, order
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    answerPath = try container.decode(String.self, forKey: .answerPath)
    title = try container.decode(String.self, forKey: .title)
    description = try container.decode(String.self, forKey: .description)
    guidance = try container.decodeIfPresent(String.self, forKey: .guidance)
    example = try container.decodeIfPresent(String.self, forKey: .example)
    placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
    stage = try container.decodeIfPresent(String.self, forKey: .stage)
    inputType = try container.decode(String.self, forKey: .inputType)
    required = try container.decode(Bool.self, forKey: .required)
    order = try container.decode(Int.self, forKey: .order)
  }
}

enum JumaoInterviewSchemaLoadResult: Equatable, Sendable {
  case succeeded(JumaoInterviewSchema)
  case failed(exitCode: Int32?, message: String)
}

@MainActor
protocol JumaoInterviewSchemaLoading {
  func run(completion: @escaping @MainActor @Sendable (JumaoInterviewSchemaLoadResult) -> Void)
}

@MainActor
final class JumaoInterviewSchemaLoader: JumaoInterviewSchemaLoading {
  nonisolated static func arguments() -> [String] {
    ["interview", "--schema"]
  }

  private let resolver: any JumaoCLIResolving
  private var runningProcess: Process?

  init(resolver: any JumaoCLIResolving = JumaoCLIResolver()) {
    self.resolver = resolver
  }

  func run(completion: @escaping @MainActor @Sendable (JumaoInterviewSchemaLoadResult) -> Void) {
    resolver.resolve { [weak self] resolution in
      guard let self else { return }

      switch resolution {
      case .resolved(let command):
        self.run(command: command, completion: completion)
      case .failed(let error):
        completion(.failed(exitCode: nil, message: error.userFacingMessage))
      }
    }
  }

  private func run(
    command: JumaoCLICommand,
    completion: @escaping @MainActor @Sendable (JumaoInterviewSchemaLoadResult) -> Void
  ) {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = command.executableURL
    process.arguments = command.arguments(for: Self.arguments())
    process.standardOutput = standardOutput
    process.standardError = standardError
    process.terminationHandler = { [weak self] process in
      let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = Self.shortMessage(from: standardError.fileHandleForReading.readDataToEndOfFile())
      let result: JumaoInterviewSchemaLoadResult

      if process.terminationStatus == 0 {
        do {
          result = .succeeded(try Self.decodeSchema(from: output))
        } catch {
          result = .failed(exitCode: process.terminationStatus, message: "Jumao 返回的问题格式无效。")
        }
      } else {
        result = .failed(
          exitCode: process.terminationStatus,
          message: errorMessage.isEmpty ? "jumao interview --schema 未能完成。" : errorMessage
        )
      }

      Task { @MainActor [weak self] in
        self?.runningProcess = nil
        completion(result)
      }
    }

    do {
      try process.run()
      runningProcess = process
    } catch {
      completion(.failed(exitCode: nil, message: error.localizedDescription))
    }
  }

  nonisolated static func decodeSchema(from data: Data) throws -> JumaoInterviewSchema {
    try JSONDecoder().decode(JumaoInterviewSchema.self, from: data)
  }

  nonisolated private static func shortMessage(from data: Data) -> String {
    JumaoCLIErrorLog.userMessage(from: data, fallback: "无法读取项目问题。", operation: "interview --schema")
  }
}
