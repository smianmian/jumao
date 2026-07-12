import Foundation

enum JumaoInterviewAnswerWriteResult: Equatable, Sendable {
  case succeeded
  case failed(exitCode: Int32?, message: String)
}

@MainActor
protocol JumaoInterviewAnswerWriting {
  func documentsWithContent(in workspaceURL: URL) -> [String]
  func run(
    workspaceURL: URL,
    questions: [JumaoInterviewQuestion],
    answers: [String: String],
    force: Bool,
    completion: @escaping @MainActor @Sendable (JumaoInterviewAnswerWriteResult) -> Void
  )
}

@MainActor
final class JumaoInterviewAnswerWriter: JumaoInterviewAnswerWriting {
  static let executableURL = URL(fileURLWithPath: "/usr/bin/env")
  static let coreDocumentPaths = [
    "product/product-brief.zh-CN.md",
    "product/scope-gate.zh-CN.md",
    "product/screen-states.zh-CN.md",
    "product/data-safety.zh-CN.md"
  ]

  private let executableURL: URL
  private let command: String?
  private let temporaryDirectory: URL
  private var runningProcess: Process?

  init(
    executableURL: URL = JumaoInterviewAnswerWriter.executableURL,
    command: String? = "jumao",
    temporaryDirectory: URL = FileManager.default.temporaryDirectory
  ) {
    self.executableURL = executableURL
    self.command = command
    self.temporaryDirectory = temporaryDirectory
  }

  nonisolated static func arguments(workspaceURL: URL, answersURL: URL, force: Bool) -> [String] {
    var arguments = ["jumao", "interview", workspaceURL.path, "--answers", answersURL.path]
    if force {
      arguments.append("--force")
    }
    return arguments
  }

  nonisolated static func makeAnswers(
    questions: [JumaoInterviewQuestion],
    answers: [String: String]
  ) -> [String: Any] {
    var nestedAnswers: [String: Any] = [:]

    for question in questions {
      let rawAnswer = answers[question.answerPath] ?? ""
      let value: Any = question.inputType == "list" ? splitListAnswer(rawAnswer) : rawAnswer
      setAnswer(value, at: question.answerPath, in: &nestedAnswers)
    }

    return nestedAnswers
  }

  nonisolated static func splitListAnswer(_ value: String) -> [String] {
    value
      .split(whereSeparator: { ",，、".contains($0) })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  func documentsWithContent(in workspaceURL: URL) -> [String] {
    Self.coreDocumentPaths.filter { relativePath in
      let fileURL = workspaceURL.appendingPathComponent(relativePath)
      guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
      return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  func run(
    workspaceURL: URL,
    questions: [JumaoInterviewQuestion],
    answers: [String: String],
    force: Bool,
    completion: @escaping @MainActor @Sendable (JumaoInterviewAnswerWriteResult) -> Void
  ) {
    let answersURL: URL
    do {
      answersURL = try writeTemporaryAnswers(questions: questions, answers: answers)
    } catch {
      completion(.failed(exitCode: nil, message: "无法准备临时答案。"))
      return
    }

    let process = Process()
    let standardError = Pipe()
    process.executableURL = executableURL
    process.arguments = processArguments(workspaceURL: workspaceURL, answersURL: answersURL, force: force)
    process.standardOutput = FileHandle.nullDevice
    process.standardError = standardError
    process.terminationHandler = { [weak self] process in
      let message = Self.shortMessage(from: standardError.fileHandleForReading.readDataToEndOfFile())
      try? FileManager.default.removeItem(at: answersURL)
      let result: JumaoInterviewAnswerWriteResult = process.terminationStatus == 0
        ? .succeeded
        : .failed(
          exitCode: process.terminationStatus,
          message: message.isEmpty ? "jumao interview 未能完成。" : message
        )

      Task { @MainActor [weak self] in
        self?.runningProcess = nil
        completion(result)
      }
    }

    do {
      try process.run()
      runningProcess = process
    } catch {
      try? FileManager.default.removeItem(at: answersURL)
      completion(.failed(exitCode: nil, message: "无法启动 jumao interview。"))
    }
  }

  private func processArguments(workspaceURL: URL, answersURL: URL, force: Bool) -> [String] {
    var arguments = Self.arguments(workspaceURL: workspaceURL, answersURL: answersURL, force: force)
    if let command {
      arguments[0] = command
    } else {
      arguments.removeFirst()
    }
    return arguments
  }

  private func writeTemporaryAnswers(
    questions: [JumaoInterviewQuestion],
    answers: [String: String]
  ) throws -> URL {
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    let fileURL = temporaryDirectory.appendingPathComponent("jumao-interview-\(UUID().uuidString).json")
    let object = Self.makeAnswers(questions: questions, answers: answers)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try data.write(to: fileURL, options: .atomic)
    return fileURL
  }

  nonisolated private static func setAnswer(_ value: Any, at answerPath: String, in answers: inout [String: Any]) {
    let parts = answerPath.split(separator: ".").map(String.init)
    guard let key = parts.first else { return }

    if parts.count == 1 {
      answers[key] = value
      return
    }

    var child = answers[key] as? [String: Any] ?? [:]
    setAnswer(value, at: parts.dropFirst().joined(separator: "."), in: &child)
    answers[key] = child
  }

  nonisolated private static func shortMessage(from data: Data) -> String {
    guard let text = String(data: data, encoding: .utf8) else {
      return "无法读取 Jumao 的错误信息。"
    }

    let normalized = text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return String(normalized.prefix(240))
  }
}
