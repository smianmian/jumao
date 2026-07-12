import Foundation

enum CodexTaskPackRunResult: Equatable, Sendable {
  case succeeded
  case failed(exitCode: Int32?, message: String)
}

@MainActor
protocol CodexTaskPackRunning {
  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (CodexTaskPackRunResult) -> Void
  )
  func cancel()
}

@MainActor
final class CodexTaskPackRunner: CodexTaskPackRunning {
  static let executableURL = URL(fileURLWithPath: "/usr/bin/env")

  nonisolated static func arguments(for workspaceURL: URL) -> [String] {
    ["jumao", "pack", workspaceURL.path, "--target", "codex"]
  }

  private var runningProcess: Process?

  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (CodexTaskPackRunResult) -> Void
  ) {
    let process = Process()
    let standardError = Pipe()
    process.executableURL = Self.executableURL
    process.arguments = Self.arguments(for: workspaceURL)
    process.standardOutput = FileHandle.nullDevice
    process.standardError = standardError
    process.terminationHandler = { [weak self] process in
      let message = Self.shortMessage(from: standardError.fileHandleForReading.readDataToEndOfFile())
      let result: CodexTaskPackRunResult = process.terminationStatus == 0
        ? .succeeded
        : .failed(
          exitCode: process.terminationStatus,
          message: message.isEmpty ? "jumao pack 未能完成。" : message
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
      completion(.failed(exitCode: nil, message: error.localizedDescription))
    }
  }

  func cancel() {
    guard let runningProcess, runningProcess.isRunning else { return }
    runningProcess.terminate()
  }

  nonisolated private static func shortMessage(from data: Data) -> String {
    guard let text = String(data: data, encoding: .utf8) else {
      return "无法读取 jumao 的错误信息。"
    }

    let normalized = text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return String(normalized.prefix(240))
  }
}
