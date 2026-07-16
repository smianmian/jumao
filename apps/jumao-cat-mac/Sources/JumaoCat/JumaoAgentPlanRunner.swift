import Foundation

enum JumaoAgentPlanRunResult: Equatable, Sendable {
  case finished
  case cancelled
  case failed(exitCode: Int32?, message: String, details: String)
}

@MainActor
protocol JumaoAgentPlanRunning: AnyObject {
  var isRunning: Bool { get }
  func run(
    workspaceURL: URL,
    force: Bool,
    event: @escaping @MainActor @Sendable (JumaoAgentPlanEvent) -> Void,
    completion: @escaping @MainActor @Sendable (JumaoAgentPlanRunResult) -> Void
  )
  func cancel()
}

@MainActor
final class JumaoAgentPlanRunner: JumaoAgentPlanRunning {
  nonisolated static func arguments(for workspaceURL: URL, force: Bool) -> [String] {
    ["plan", workspaceURL.path, "--events-jsonl"] + (force ? ["--force"] : [])
  }

  private let resolver: any JumaoCLIResolving
  private var runningProcess: Process?
  private var currentCompletion: (@MainActor @Sendable (JumaoAgentPlanRunResult) -> Void)?
  private var wasCancelled = false

  var isRunning: Bool { runningProcess?.isRunning == true || currentCompletion != nil }

  init(resolver: any JumaoCLIResolving = JumaoCLIResolver()) {
    self.resolver = resolver
  }

  func run(
    workspaceURL: URL,
    force: Bool,
    event: @escaping @MainActor @Sendable (JumaoAgentPlanEvent) -> Void,
    completion: @escaping @MainActor @Sendable (JumaoAgentPlanRunResult) -> Void
  ) {
    guard !isRunning else {
      completion(.failed(exitCode: nil, message: "当前项目正在整理中。", details: "拒绝启动重复的 jumao plan 进程。"))
      return
    }
    currentCompletion = completion
    wasCancelled = false
    resolver.resolve { [weak self] resolution in
      guard let self else { return }
      guard self.currentCompletion != nil, !self.wasCancelled else { return }
      switch resolution {
      case .resolved(let command):
        self.start(workspaceURL: workspaceURL, force: force, command: command, event: event)
      case .failed(let error):
        self.finish(.failed(exitCode: nil, message: error.userFacingMessage, details: error.userFacingMessage))
      }
    }
  }

  private func start(
    workspaceURL: URL,
    force: Bool,
    command: JumaoCLICommand,
    event: @escaping @MainActor @Sendable (JumaoAgentPlanEvent) -> Void
  ) {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    let stream = JumaoAgentJSONLStream()
    process.executableURL = command.executableURL
    process.arguments = command.arguments(for: Self.arguments(for: workspaceURL, force: force))
    process.standardOutput = stdout
    process.standardError = stderr

    stdout.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      for decoded in stream.append(data) {
        Task { @MainActor in event(decoded) }
      }
    }
    process.terminationHandler = { [weak self] process in
      stdout.fileHandleForReading.readabilityHandler = nil
      let remaining = stdout.fileHandleForReading.readDataToEndOfFile()
      let finalEvents = stream.append(remaining) + stream.finish()
      let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
      let details = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let parseError = stream.errorDescription
      Task { @MainActor [weak self] in
        for decoded in finalEvents { event(decoded) }
        guard let self else { return }
        if self.wasCancelled {
          self.finish(.cancelled)
        } else if let parseError {
          self.finish(.failed(
            exitCode: process.terminationStatus,
            message: "规划进度数据无法读取。",
            details: parseError
          ))
        } else if process.terminationStatus == 0 {
          self.finish(.finished)
        } else {
          self.finish(.failed(
            exitCode: process.terminationStatus,
            message: "橘猫没有完成这次整理。",
            details: details.isEmpty ? "jumao plan 退出码：\(process.terminationStatus)" : details
          ))
        }
      }
    }

    do {
      try process.run()
      runningProcess = process
    } catch {
      stdout.fileHandleForReading.readabilityHandler = nil
      finish(.failed(exitCode: nil, message: "无法启动 Jumao 规划运行时。", details: error.localizedDescription))
    }
  }

  func cancel() {
    guard currentCompletion != nil else { return }
    wasCancelled = true
    if let process = runningProcess, process.isRunning {
      process.terminate()
    } else {
      finish(.cancelled)
    }
  }

  private func finish(_ result: JumaoAgentPlanRunResult) {
    let completion = currentCompletion
    currentCompletion = nil
    runningProcess = nil
    completion?(result)
  }
}

private final class JumaoAgentJSONLStream: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer = Data()
  private var storedError: String?

  var errorDescription: String? {
    lock.withLock { storedError }
  }

  func append(_ data: Data) -> [JumaoAgentPlanEvent] {
    lock.withLock {
      guard storedError == nil else { return [] }
      buffer.append(data)
      var events: [JumaoAgentPlanEvent] = []
      while let newline = buffer.firstIndex(of: 0x0A) {
        let line = buffer[..<newline]
        buffer.removeSubrange(...newline)
        guard !line.isEmpty else { continue }
        do {
          events.append(try JSONDecoder().decode(JumaoAgentPlanEvent.self, from: Data(line)))
        } catch {
          storedError = "JSONL 解析失败：\(error.localizedDescription)"
          return events
        }
      }
      return events
    }
  }

  func finish() -> [JumaoAgentPlanEvent] {
    lock.withLock {
      guard storedError == nil, !buffer.isEmpty else { return [] }
      defer { buffer.removeAll() }
      do {
        return [try JSONDecoder().decode(JumaoAgentPlanEvent.self, from: buffer)]
      } catch {
        storedError = "JSONL 最后一行不完整：\(error.localizedDescription)"
        return []
      }
    }
  }
}
