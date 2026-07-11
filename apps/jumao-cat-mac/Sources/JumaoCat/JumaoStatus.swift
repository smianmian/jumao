import Foundation

struct JumaoCatStatus: Decodable {
  let schemaVersion: String
  let jumaoVersion: String
  let updatedAt: String?
  let workspace: Workspace
  let cat: Cat
  let agentBoard: AgentBoard
  let blockers: [Blocker]
  let nextSafeTask: String
  let artifacts: Artifacts
  let lastRun: LastRun

  enum CodingKeys: String, CodingKey {
    case schemaVersion
    case jumaoVersion
    case updatedAt
    case workspace
    case cat
    case agentBoard
    case blockers
    case nextSafeTask
    case artifacts
    case lastRun
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = (try? container.decode(String.self, forKey: .schemaVersion)) ?? ""
    jumaoVersion = (try? container.decode(String.self, forKey: .jumaoVersion)) ?? ""
    updatedAt = try? container.decode(String.self, forKey: .updatedAt)
    workspace = (try? container.decode(Workspace.self, forKey: .workspace)) ?? .empty
    cat = try container.decode(Cat.self, forKey: .cat)
    agentBoard = (try? container.decode(AgentBoard.self, forKey: .agentBoard)) ?? .empty
    blockers = (try? container.decode([Blocker].self, forKey: .blockers)) ?? []
    nextSafeTask = (try? container.decode(String.self, forKey: .nextSafeTask)) ?? ""
    artifacts = (try? container.decode(Artifacts.self, forKey: .artifacts)) ?? .empty
    lastRun = (try? container.decode(LastRun.self, forKey: .lastRun)) ?? .empty
  }

  struct Workspace: Decodable {
    let name: String
    let path: String

    static let empty = Workspace(name: "", path: "")

    init(name: String, path: String) {
      self.name = name
      self.path = path
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      name = (try? container.decode(String.self, forKey: .name)) ?? ""
      path = (try? container.decode(String.self, forKey: .path)) ?? ""
    }

    enum CodingKeys: String, CodingKey {
      case name
      case path
    }
  }

  struct Cat: Decodable {
    let state: String
    let label: String
    let message: String
  }

  struct AgentBoard: Decodable {
    let triggeredAgentCount: Int
    let activeGroupCount: Int
    let blockedGroupCount: Int

    static let empty = AgentBoard(triggeredAgentCount: 0, activeGroupCount: 0, blockedGroupCount: 0)

    init(triggeredAgentCount: Int, activeGroupCount: Int, blockedGroupCount: Int) {
      self.triggeredAgentCount = triggeredAgentCount
      self.activeGroupCount = activeGroupCount
      self.blockedGroupCount = blockedGroupCount
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      triggeredAgentCount = (try? container.decode(Int.self, forKey: .triggeredAgentCount)) ?? 0
      activeGroupCount = (try? container.decode(Int.self, forKey: .activeGroupCount)) ?? 0
      blockedGroupCount = (try? container.decode(Int.self, forKey: .blockedGroupCount)) ?? 0
    }

    enum CodingKeys: String, CodingKey {
      case triggeredAgentCount
      case activeGroupCount
      case blockedGroupCount
    }
  }

  struct Blocker: Decodable, Identifiable {
    let title: String
    let message: String
    let source: String

    var id: String { "\(title)-\(message)-\(source)" }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      title = (try? container.decode(String.self, forKey: .title)) ?? "未命名阻塞"
      message = (try? container.decode(String.self, forKey: .message)) ?? ""
      source = (try? container.decode(String.self, forKey: .source)) ?? ""
    }

    enum CodingKeys: String, CodingKey {
      case title
      case message
      case source
    }
  }

  struct Artifacts: Decodable {
    let agentReport: String
    let agentFindings: String
    let codexGates: String
    let latestTaskPack: String

    static let empty = Artifacts(agentReport: "", agentFindings: "", codexGates: "", latestTaskPack: "")

    init(agentReport: String, agentFindings: String, codexGates: String, latestTaskPack: String) {
      self.agentReport = agentReport
      self.agentFindings = agentFindings
      self.codexGates = codexGates
      self.latestTaskPack = latestTaskPack
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      agentReport = (try? container.decode(String.self, forKey: .agentReport)) ?? ""
      agentFindings = (try? container.decode(String.self, forKey: .agentFindings)) ?? ""
      codexGates = (try? container.decode(String.self, forKey: .codexGates)) ?? ""
      latestTaskPack = (try? container.decode(String.self, forKey: .latestTaskPack)) ?? ""
    }

    enum CodingKeys: String, CodingKey {
      case agentReport
      case agentFindings
      case codexGates
      case latestTaskPack
    }
  }

  struct LastRun: Decodable {
    let command: String?
    let target: String?
    let ok: Bool?

    static let empty = LastRun(command: nil, target: nil, ok: nil)

    init(command: String?, target: String?, ok: Bool?) {
      self.command = command
      self.target = target
      self.ok = ok
    }
  }
}

enum WorkspaceStatus {
  case unselected
  case missingStatusFile
  case loaded(StatusSnapshot)
  case failed(String)

  var catState: String {
    switch self {
    case .unselected, .missingStatusFile:
      return "sleeping"
    case .loaded(let snapshot):
      return snapshot.status.cat.state
    case .failed:
      return "blocked"
    }
  }

  var label: String {
    switch self {
    case .unselected:
      return CatStatePresentation.forState("sleeping").label
    case .missingStatusFile:
      return "这个项目还没有完成检查"
    case .loaded(let snapshot):
      return CatStatePresentation.forState(snapshot.status.cat.state).label
    case .failed:
      return "无法读取"
    }
  }

  var message: String {
    switch self {
    case .unselected:
      return CatStatePresentation.forState("sleeping").message
    case .missingStatusFile:
      return "运行 Jumao 检查后，这里会显示项目状态"
    case .loaded(let snapshot):
      return CatStatePresentation.forState(snapshot.status.cat.state).message
    case .failed(let message):
      return message
    }
  }

  var snapshot: StatusSnapshot? {
    guard case .loaded(let snapshot) = self else { return nil }
    return snapshot
  }

  var projectReadiness: ProjectReadiness? {
    switch self {
    case .unselected:
      return nil
    case .missingStatusFile:
      return .waitingForCheck
    case .loaded(let snapshot):
      return ProjectReadiness.forState(snapshot.status.cat.state)
    case .failed:
      return ProjectReadiness.forState("blocked")
    }
  }

  var agentTeamOverview: AgentTeamOverview? {
    guard case .loaded(let snapshot) = self else { return nil }
    return AgentTeamOverview(
      agentBoard: snapshot.status.agentBoard,
      catState: snapshot.status.cat.state
    )
  }
}

struct CatStatePresentation: Equatable {
  let label: String
  let message: String

  static func forState(_ state: String) -> CatStatePresentation {
    switch state {
    case "sleeping":
      return CatStatePresentation(label: "待命", message: "项目尚未开始检查")
    case "checking":
      return CatStatePresentation(label: "检查中", message: "橘猫正在分析项目目标、边界和风险")
    case "blocked":
      return CatStatePresentation(label: "存在阻塞", message: "发现关键问题，处理后才能继续")
    case "ready":
      return CatStatePresentation(label: "准备完成", message: "项目检查已通过，可以生成任务包")
    case "packed":
      return CatStatePresentation(label: "任务包已生成", message: "任务已经整理完成，可以交给 Codex 执行")
    default:
      let rawState = state.isEmpty ? "空值" : state
      return CatStatePresentation(label: "未知状态", message: "原始状态码：\(rawState)")
    }
  }
}

struct ProjectReadiness: Equatable {
  let percentage: Int
  let stage: String
  let rawState: String?

  static let waitingForCheck = ProjectReadiness(
    percentage: 10,
    stage: "等待检查",
    rawState: nil
  )

  static func forState(_ state: String) -> ProjectReadiness {
    switch state {
    case "sleeping":
      return ProjectReadiness(percentage: 20, stage: "待命", rawState: nil)
    case "checking":
      return ProjectReadiness(percentage: 40, stage: "正在检查", rawState: nil)
    case "blocked":
      return ProjectReadiness(percentage: 60, stage: "处理阻塞", rawState: nil)
    case "ready":
      return ProjectReadiness(percentage: 80, stage: "准备生成任务包", rawState: nil)
    case "packed":
      return ProjectReadiness(percentage: 100, stage: "任务包已生成", rawState: nil)
    default:
      return ProjectReadiness(
        percentage: 20,
        stage: "未知阶段",
        rawState: state.isEmpty ? "空值" : state
      )
    }
  }
}

struct AgentTeamOverview {
  let triggeredAgentCount: Int
  let activeGroupCount: Int
  let blockedGroupCount: Int
  let showsCheckingActivity: Bool

  init(agentBoard: JumaoCatStatus.AgentBoard, catState: String) {
    triggeredAgentCount = agentBoard.triggeredAgentCount
    activeGroupCount = agentBoard.activeGroupCount
    blockedGroupCount = agentBoard.blockedGroupCount
    showsCheckingActivity = catState == "checking"
  }
}

struct StatusReader {
  func read(workspaceURL: URL) -> WorkspaceStatus {
    let statusURL = workspaceURL.appendingPathComponent(".jumao/status.json")

    guard FileManager.default.fileExists(atPath: statusURL.path) else {
      return .missingStatusFile
    }

    do {
      let data = try Data(contentsOf: statusURL)
      let status = try JSONDecoder().decode(JumaoCatStatus.self, from: data)
      let resourceValues = try? statusURL.resourceValues(forKeys: [.contentModificationDateKey])
      return .loaded(StatusSnapshot(
        workspaceURL: workspaceURL,
        statusURL: statusURL,
        status: status,
        fileModificationDate: resourceValues?.contentModificationDate
      ))
    } catch {
      return .failed(".jumao/status.json 无法读取：\(error.localizedDescription)")
    }
  }
}

struct StatusSnapshot {
  let workspaceURL: URL
  let statusURL: URL
  let status: JumaoCatStatus
  let fileModificationDate: Date?
}
