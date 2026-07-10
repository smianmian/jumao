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
      return "还没有选择项目"
    case .missingStatusFile:
      return "还没检查"
    case .loaded(let snapshot):
      return snapshot.status.cat.label
    case .failed:
      return "无法读取"
    }
  }

  var message: String {
    switch self {
    case .unselected:
      return "请选择一个 Jumao 项目目录。"
    case .missingStatusFile:
      return "项目中还没有 .jumao/status.json。"
    case .loaded(let snapshot):
      return snapshot.status.cat.message
    case .failed(let message):
      return message
    }
  }

  var snapshot: StatusSnapshot? {
    guard case .loaded(let snapshot) = self else { return nil }
    return snapshot
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
