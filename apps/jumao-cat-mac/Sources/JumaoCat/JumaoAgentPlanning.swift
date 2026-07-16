import Foundation

struct JumaoAgentCounts: Codable, Equatable, Sendable {
  var completed: Int
  var skipped: Int
  var blocked: Int
  var failed: Int

  static let zero = JumaoAgentCounts(completed: 0, skipped: 0, blocked: 0, failed: 0)
  var total: Int { completed + skipped + blocked + failed }
}

struct JumaoAgentGroupDescriptor: Codable, Equatable, Sendable {
  let groupId: String
  let groupName: String
  let totalAgents: Int
}

struct JumaoAgentPlanEvent: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let runId: String?
  let timestamp: String
  let event: String
  let groupId: String?
  let groupName: String?
  let agentId: String?
  let agentName: String?
  let agentStatus: String?
  let completedAgents: Int
  let skippedAgents: Int
  let blockedAgents: Int
  let failedAgents: Int
  let totalAgents: Int
  let groupCounts: JumaoAgentCounts?
  let summary: String?
  let skippedReason: String?
  let state: String?
  let reused: Bool
  let runPath: String?
  let error: String?
  let groups: [JumaoAgentGroupDescriptor]?

  var counts: JumaoAgentCounts {
    JumaoAgentCounts(
      completed: completedAgents,
      skipped: skippedAgents,
      blocked: blockedAgents,
      failed: failedAgents
    )
  }
}

enum JumaoAgentProgressStatus: String, Codable, Equatable, Sendable {
  case waiting
  case working
  case completed
  case skipped
  case blocked
  case failed
}

struct JumaoAgentProgress: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  var status: JumaoAgentProgressStatus
  var summary: String?
  var skippedReason: String?
}

struct JumaoAgentGroupProgress: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let totalAgents: Int
  var status: JumaoAgentProgressStatus
  var counts: JumaoAgentCounts
  var summary: String?
  var agents: [JumaoAgentProgress]
}

enum JumaoAgentPlanningPhase: Equatable, Sendable {
  case running
  case completed
  case interrupted
  case failed
  case cancelled
}

struct JumaoAgentPlanningSession: Equatable, Sendable {
  var phase: JumaoAgentPlanningPhase
  var workspaceIdentifier: String
  var runId: String?
  var runPath: String?
  var state: String?
  var reused: Bool
  var counts: JumaoAgentCounts
  var totalAgents: Int
  var groups: [JumaoAgentGroupProgress]
  var request: String?
  var understanding: String?
  var errorMessage: String?
  var errorDetails: String?

  static func running(workspaceIdentifier: String) -> Self {
    JumaoAgentPlanningSession(
      phase: .running,
      workspaceIdentifier: workspaceIdentifier,
      runId: nil,
      runPath: nil,
      state: nil,
      reused: false,
      counts: .zero,
      totalAgents: 44,
      groups: [],
      request: nil,
      understanding: nil,
      errorMessage: nil,
      errorDetails: nil
    )
  }

  mutating func apply(_ event: JumaoAgentPlanEvent) {
    runId = event.runId ?? runId
    runPath = event.runPath ?? runPath
    state = event.state ?? state
    reused = event.reused
    counts = event.counts
    totalAgents = event.totalAgents

    if let descriptors = event.groups {
      groups = descriptors.map {
        JumaoAgentGroupProgress(
          id: $0.groupId,
          name: $0.groupName,
          totalAgents: $0.totalAgents,
          status: .waiting,
          counts: .zero,
          summary: nil,
          agents: []
        )
      }
    }

    guard let groupId = event.groupId,
          let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else { return }
    if event.event == "group.started" {
      groups[groupIndex].status = .working
    } else if event.event == "group.completed" {
      groups[groupIndex].status = groupStatus(for: event.groupCounts ?? groups[groupIndex].counts)
      groups[groupIndex].summary = event.summary
    }
    if let groupCounts = event.groupCounts {
      groups[groupIndex].counts = groupCounts
      if event.agentStatus == "failed" || event.agentStatus == "blocked" {
        groups[groupIndex].status = groupStatus(for: groupCounts)
      }
    }
    guard event.event.hasPrefix("agent."),
          let agentId = event.agentId,
          let agentStatus = event.agentStatus.flatMap(JumaoAgentProgressStatus.init(rawValue:)) else { return }
    let agent = JumaoAgentProgress(
      id: agentId,
      name: event.agentName ?? agentId,
      status: agentStatus,
      summary: event.summary,
      skippedReason: event.skippedReason
    )
    if let index = groups[groupIndex].agents.firstIndex(where: { $0.id == agentId }) {
      groups[groupIndex].agents[index] = agent
    } else {
      groups[groupIndex].agents.append(agent)
    }
  }

  private func groupStatus(for counts: JumaoAgentCounts) -> JumaoAgentProgressStatus {
    if counts.failed > 0 { return .failed }
    if counts.blocked > 0 { return .blocked }
    if counts.completed == 0, counts.skipped > 0 { return .skipped }
    return .completed
  }
}

enum JumaoAgentPlanLoadResult: Equatable, Sendable {
  case missing
  case loaded(JumaoAgentPlanningSession)
  case interrupted(JumaoAgentPlanningSession)
  case invalid(message: String, details: String)

  var loadedSession: JumaoAgentPlanningSession? {
    switch self {
    case .loaded(let session), .interrupted(let session): session
    case .missing, .invalid: nil
    }
  }
}

protocol JumaoAgentPlanLoading: Sendable {
  func load(workspaceURL: URL) -> JumaoAgentPlanLoadResult
}

struct JumaoAgentPlanLoader: JumaoAgentPlanLoading {
  private struct LatestRun: Decodable {
    let runId: String
    let runPath: String
    let state: String
    let counts: JumaoAgentCounts
  }

  private struct Manifest: Decodable {
    struct AgentEntry: Decodable {
      let agentId: String
      let agentName: String?
      let groupId: String
      let status: String
      let output: String
    }
    struct GroupEntry: Decodable { let groupId: String; let counts: JumaoAgentCounts; let output: String }
    let schemaVersion: Int
    let runId: String
    let state: String
    let counts: JumaoAgentCounts
    let agents: [AgentEntry]
    let groups: [GroupEntry]
    let artifacts: Artifacts
    struct Artifacts: Decodable { let planningSummary: String; let taskPlan: String; let publishedTaskPlan: String }
  }

  private struct AgentOutput: Decodable {
    let agentId: String
    let groupId: String
    let status: String
    let summary: String
    let skippedReason: String?
  }

  private struct GroupOutput: Decodable {
    let groupId: String
    let groupName: String
    let counts: JumaoAgentCounts
    let mainFindings: [String]
    let agentStatuses: [AgentStatus]
    struct AgentStatus: Decodable { let agentId: String; let status: String }
  }

  private struct TaskPlan: Decodable {
    let request: String
    let understanding: String
  }

  func load(workspaceURL: URL) -> JumaoAgentPlanLoadResult {
    let fileManager = FileManager.default
    let latestURL = workspaceURL.appendingPathComponent(".jumao/latest-run.json")
    guard fileManager.fileExists(atPath: latestURL.path) else {
      return interruptedSessionIfNeeded(workspaceURL: workspaceURL) ?? .missing
    }

    do {
      let latest: LatestRun = try decode(LatestRun.self, at: latestURL)
      let runURL = try safeURL(relativePath: latest.runPath, workspaceURL: workspaceURL)
      let manifest: Manifest = try decode(Manifest.self, at: runURL.appendingPathComponent("manifest.json"))
      guard manifest.schemaVersion == 1, manifest.runId == latest.runId else {
        throw LoadError.invalid("运行清单版本或编号不一致。")
      }
      guard manifest.agents.count == 44, manifest.groups.count == 8 else {
        throw LoadError.invalid("规划产物不完整：应包含 44 个角色和 8 个小组。")
      }
      guard manifest.counts == latest.counts, manifest.counts.total == 44 else {
        throw LoadError.invalid("规划统计与运行清单不一致。")
      }
      let publishedPlanURL = try safeURL(relativePath: manifest.artifacts.publishedTaskPlan, workspaceURL: workspaceURL)
      guard fileManager.fileExists(atPath: publishedPlanURL.path) else {
        throw LoadError.invalid("缺少 tasks/jumao-agent-plan.md。")
      }
      guard fileManager.fileExists(atPath: runURL.appendingPathComponent(manifest.artifacts.planningSummary).path),
            fileManager.fileExists(atPath: runURL.appendingPathComponent(manifest.artifacts.taskPlan).path) else {
        throw LoadError.invalid("缺少规划摘要或任务计划。")
      }

      let taskPlan: TaskPlan = try decode(TaskPlan.self, at: runURL.appendingPathComponent(manifest.artifacts.taskPlan))
      let agentOutputs = try Dictionary(uniqueKeysWithValues: manifest.agents.map { entry in
        let output: AgentOutput = try decode(AgentOutput.self, at: runURL.appendingPathComponent(entry.output))
        guard output.agentId == entry.agentId, output.groupId == entry.groupId, output.status == entry.status else {
          throw LoadError.invalid("角色产物与 manifest 不一致：\(entry.agentId)")
        }
        return (output.agentId, (output: output, name: entry.agentName ?? displayName(for: entry.agentId)))
      })
      let groups = try manifest.groups.map { entry -> JumaoAgentGroupProgress in
        let output: GroupOutput = try decode(GroupOutput.self, at: runURL.appendingPathComponent(entry.output))
        guard output.groupId == entry.groupId, output.counts == entry.counts else {
          throw LoadError.invalid("小组产物与 manifest 不一致：\(entry.groupId)")
        }
        let agents = try output.agentStatuses.map { status -> JumaoAgentProgress in
          guard let entry = agentOutputs[status.agentId], entry.output.status == status.status,
                let progressStatus = JumaoAgentProgressStatus(rawValue: status.status) else {
            throw LoadError.invalid("小组角色状态不一致：\(status.agentId)")
          }
          return JumaoAgentProgress(
            id: entry.output.agentId,
            name: entry.name,
            status: progressStatus,
            summary: entry.output.summary,
            skippedReason: entry.output.skippedReason
          )
        }
        return JumaoAgentGroupProgress(
          id: output.groupId,
          name: output.groupName,
          totalAgents: agents.count,
          status: groupStatus(output.counts),
          counts: output.counts,
          summary: output.mainFindings.first,
          agents: agents
        )
      }
      let phase: JumaoAgentPlanningPhase = latest.state == "checking" ? .interrupted : .completed
      let session = JumaoAgentPlanningSession(
        phase: phase,
        workspaceIdentifier: workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path,
        runId: latest.runId,
        runPath: latest.runPath,
        state: latest.state,
        reused: false,
        counts: latest.counts,
        totalAgents: 44,
        groups: groups,
        request: taskPlan.request,
        understanding: taskPlan.understanding,
        errorMessage: phase == .interrupted ? "上次整理没有完成" : nil,
        errorDetails: phase == .interrupted ? "latest run 仍处于 checking 状态。" : nil
      )
      return phase == .interrupted ? .interrupted(session) : .loaded(session)
    } catch {
      return .invalid(message: "上次规划资料无法读取", details: String(describing: error))
    }
  }

  private func interruptedSessionIfNeeded(workspaceURL: URL) -> JumaoAgentPlanLoadResult? {
    let statusURL = workspaceURL.appendingPathComponent(".jumao/status.json")
    guard let data = try? Data(contentsOf: statusURL),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cat = object["cat"] as? [String: Any], cat["state"] as? String == "checking" else { return nil }
    let session = JumaoAgentPlanningSession(
      phase: .interrupted,
      workspaceIdentifier: workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path,
      runId: object["runId"] as? String,
      runPath: object["runPath"] as? String,
      state: "checking",
      reused: false,
      counts: .zero,
      totalAgents: object["totalAgents"] as? Int ?? 44,
      groups: [],
      request: nil,
      understanding: nil,
      errorMessage: "上次整理没有完成",
      errorDetails: "项目状态停留在 checking，但没有完整的 latest run。"
    )
    return .interrupted(session)
  }

  private func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }

  private func safeURL(relativePath: String, workspaceURL: URL) throws -> URL {
    guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { throw LoadError.invalid("运行路径无效。") }
    let root = workspaceURL.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = root.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
    guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
      throw LoadError.invalid("运行路径超出当前项目。")
    }
    return candidate
  }

  private func groupStatus(_ counts: JumaoAgentCounts) -> JumaoAgentProgressStatus {
    if counts.failed > 0 { return .failed }
    if counts.blocked > 0 { return .blocked }
    if counts.completed == 0, counts.skipped > 0 { return .skipped }
    return .completed
  }

  private func displayName(for id: String) -> String {
    id.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
  }

  private enum LoadError: Error {
    case invalid(String)
  }
}
