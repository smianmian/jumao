import Foundation

struct JumaoInterviewSchema: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let questions: [JumaoInterviewQuestion]
}

struct JumaoInterviewQuestion: Codable, Equatable, Sendable {
  let id: String
  let answerPath: String
  let title: String
  let description: String
  let inputType: String
  let required: Bool
  let order: Int
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
  static let executableURL = URL(fileURLWithPath: "/usr/bin/env")

  nonisolated static func arguments() -> [String] {
    ["jumao", "interview", "--schema"]
  }

  private var runningProcess: Process?

  func run(completion: @escaping @MainActor @Sendable (JumaoInterviewSchemaLoadResult) -> Void) {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = Self.executableURL
    process.arguments = Self.arguments()
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
