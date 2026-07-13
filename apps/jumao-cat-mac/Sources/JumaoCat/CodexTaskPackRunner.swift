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
  nonisolated static func arguments(for workspaceURL: URL) -> [String] {
    ["pack", workspaceURL.path, "--target", "codex"]
  }

  private let resolver: any JumaoCLIResolving
  private var runningProcess: Process?

  init(resolver: any JumaoCLIResolving = JumaoCLIResolver()) {
    self.resolver = resolver
  }

  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (CodexTaskPackRunResult) -> Void
  ) {
    resolver.resolve { [weak self] resolution in
      guard let self else { return }

      switch resolution {
      case .resolved(let command):
        self.run(workspaceURL: workspaceURL, command: command, completion: completion)
      case .failed(let error):
        completion(.failed(exitCode: nil, message: error.userFacingMessage))
      }
    }
  }

  private func run(
    workspaceURL: URL,
    command: JumaoCLICommand,
    completion: @escaping @MainActor @Sendable (CodexTaskPackRunResult) -> Void
  ) {
    let process = Process()
    let standardError = Pipe()
    process.executableURL = command.executableURL
    process.arguments = command.arguments(for: Self.arguments(for: workspaceURL))
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
    JumaoCLIErrorLog.userMessage(from: data, fallback: "无法生成任务包。", operation: "pack --target codex")
  }
}
