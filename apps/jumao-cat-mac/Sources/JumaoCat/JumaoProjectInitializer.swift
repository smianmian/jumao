import Foundation

enum JumaoProjectInitializationResult: Equatable, Sendable {
  case succeeded
  case failed(exitCode: Int32?, message: String)
}

@MainActor
protocol JumaoProjectInitializing {
  func conflictingFiles(in workspaceURL: URL) -> [String]
  func run(
    projectName: String,
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoProjectInitializationResult) -> Void
  )
}

@MainActor
final class JumaoProjectInitializer: JumaoProjectInitializing {
  static let targetFiles = [
    "AGENTS.md",
    "CLAUDE.md",
    "README.md",
    "README.zh-CN.md",
    "product/product-brief.md",
    "product/product-brief.zh-CN.md",
    "product/scope-gate.md",
    "product/scope-gate.zh-CN.md",
    "product/screen-states.md",
    "product/screen-states.zh-CN.md",
    "product/data-safety.md",
    "product/data-safety.zh-CN.md",
    "proof/release-proof.md",
    "proof/release-proof.zh-CN.md"
  ]

  nonisolated static func arguments(projectName: String, workspaceURL: URL) -> [String] {
    ["new", projectName, "--dir", workspaceURL.path]
  }

  private let resolver: any JumaoCLIResolving
  private var runningProcess: Process?

  init(resolver: any JumaoCLIResolving = JumaoCLIResolver()) {
    self.resolver = resolver
  }

  func conflictingFiles(in workspaceURL: URL) -> [String] {
    let fileManager = FileManager.default
    return Self.targetFiles.filter { relativePath in
      fileManager.fileExists(atPath: workspaceURL.appendingPathComponent(relativePath).path)
    }
  }

  func run(
    projectName: String,
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoProjectInitializationResult) -> Void
  ) {
    resolver.resolve { [weak self] resolution in
      guard let self else { return }

      switch resolution {
      case .resolved(let command):
        self.run(projectName: projectName, workspaceURL: workspaceURL, command: command, completion: completion)
      case .failed(let error):
        completion(.failed(exitCode: nil, message: error.userFacingMessage))
      }
    }
  }

  private func run(
    projectName: String,
    workspaceURL: URL,
    command: JumaoCLICommand,
    completion: @escaping @MainActor @Sendable (JumaoProjectInitializationResult) -> Void
  ) {
    let process = Process()
    let standardError = Pipe()
    process.executableURL = command.executableURL
    process.arguments = command.arguments(for: Self.arguments(projectName: projectName, workspaceURL: workspaceURL))
    process.standardOutput = FileHandle.nullDevice
    process.standardError = standardError
    process.terminationHandler = { [weak self] process in
      let message = Self.shortMessage(from: standardError.fileHandleForReading.readDataToEndOfFile())
      let result: JumaoProjectInitializationResult = process.terminationStatus == 0
        ? .succeeded
        : .failed(
          exitCode: process.terminationStatus,
          message: message.isEmpty ? "jumao new 未能完成。" : message
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

  nonisolated private static func shortMessage(from data: Data) -> String {
    JumaoCLIErrorLog.userMessage(from: data, fallback: "无法建立项目。", operation: "new")
  }
}
