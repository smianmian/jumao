import Foundation

struct JumaoProjectInspection: Decodable, Equatable, Sendable {
  let schemaVersion: Int
  let workspaceKind: String
  let project: Project
  let capabilityFit: CapabilityFit
  let evidence: [Evidence]
  let unknowns: [String]
  let recommendedIntake: RecommendedIntake

  struct Project: Decodable, Equatable, Sendable {
    let name: String
    let platforms: [String]
    let languages: [String]
    let buildSystems: [String]
    let hasSourceCode: Bool
    let hasTests: Bool
    let hasJumaoFiles: Bool
  }

  struct CapabilityFit: Decodable, Equatable, Sendable {
    let level: String
    let primaryFocus: String
    let message: String
  }

  struct Evidence: Decodable, Equatable, Sendable {
    let kind: String
    let file: String
    let detail: String
  }

  struct RecommendedIntake: Decodable, Equatable, Sendable {
    let mode: String
    let questions: [String]
  }
}

enum JumaoProjectInspectionResult: Equatable, Sendable {
  case succeeded(JumaoProjectInspection)
  case failed(exitCode: Int32?, message: String)
}

@MainActor
protocol JumaoProjectInspecting {
  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoProjectInspectionResult) -> Void
  )
  func cancel()
}

@MainActor
final class JumaoProjectInspector: JumaoProjectInspecting {
  nonisolated static func arguments(for workspaceURL: URL) -> [String] {
    ["inspect", workspaceURL.path, "--json"]
  }

  private let resolver: any JumaoCLIResolving
  private var runningProcess: Process?

  init(resolver: any JumaoCLIResolving = JumaoCLIResolver()) {
    self.resolver = resolver
  }

  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoProjectInspectionResult) -> Void
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

  func cancel() {
    guard let runningProcess, runningProcess.isRunning else { return }
    runningProcess.terminate()
  }

  nonisolated static func decodeInspection(from data: Data) throws -> JumaoProjectInspection {
    try JSONDecoder().decode(JumaoProjectInspection.self, from: data)
  }

  private func run(
    workspaceURL: URL,
    command: JumaoCLICommand,
    completion: @escaping @MainActor @Sendable (JumaoProjectInspectionResult) -> Void
  ) {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = command.executableURL
    process.arguments = command.arguments(for: Self.arguments(for: workspaceURL))
    process.standardOutput = standardOutput
    process.standardError = standardError
    process.terminationHandler = { [weak self] process in
      let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
      let standardErrorData = standardError.fileHandleForReading.readDataToEndOfFile()
      let result: JumaoProjectInspectionResult

      if process.terminationStatus == 0, let inspection = try? Self.decodeInspection(from: output) {
        result = .succeeded(inspection)
      } else {
        if let stderr = String(data: standardErrorData, encoding: .utf8), !stderr.isEmpty {
          NSLog("Jumao inspect stderr: %@", stderr)
        }
        result = .failed(exitCode: process.terminationStatus, message: "无法读取项目扫描结果，请重试。")
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
      completion(.failed(exitCode: nil, message: "无法读取项目扫描结果，请重试。"))
    }
  }
}
