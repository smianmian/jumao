import CryptoKit
import Foundation

struct InterviewDraft: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let workspaceIdentifier: String
  let mode: ProjectInterviewMode?
  let currentQuestionIndex: Int
  let answers: [String: String]
  let skippedAnswerPaths: [String]
  let isInterviewComplete: Bool
  let stageID: String?
  let isCurrentStageComplete: Bool
  let updatedAt: Date

  init(
    schemaVersion: Int,
    workspaceIdentifier: String,
    mode: ProjectInterviewMode? = nil,
    currentQuestionIndex: Int,
    answers: [String: String],
    skippedAnswerPaths: [String] = [],
    isInterviewComplete: Bool = false,
    stageID: String? = nil,
    isCurrentStageComplete: Bool = false,
    updatedAt: Date
  ) {
    self.schemaVersion = schemaVersion
    self.workspaceIdentifier = workspaceIdentifier
    self.mode = mode
    self.currentQuestionIndex = currentQuestionIndex
    self.answers = answers
    self.skippedAnswerPaths = skippedAnswerPaths
    self.isInterviewComplete = isInterviewComplete
    self.stageID = stageID
    self.isCurrentStageComplete = isCurrentStageComplete
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion, workspaceIdentifier, mode, currentQuestionIndex, answers, skippedAnswerPaths, isInterviewComplete, stageID, isCurrentStageComplete, updatedAt
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    workspaceIdentifier = try container.decode(String.self, forKey: .workspaceIdentifier)
    mode = try container.decodeIfPresent(ProjectInterviewMode.self, forKey: .mode)
    currentQuestionIndex = try container.decode(Int.self, forKey: .currentQuestionIndex)
    answers = try container.decode([String: String].self, forKey: .answers)
    skippedAnswerPaths = try container.decodeIfPresent([String].self, forKey: .skippedAnswerPaths) ?? []
    isInterviewComplete = try container.decodeIfPresent(Bool.self, forKey: .isInterviewComplete) ?? false
    stageID = try container.decodeIfPresent(String.self, forKey: .stageID)
    isCurrentStageComplete = try container.decodeIfPresent(Bool.self, forKey: .isCurrentStageComplete) ?? false
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
  }
}

enum InterviewDraftLoadResult: Equatable, Sendable {
  case missing
  case loaded(InterviewDraft)
  case corrupted(reason: String)
}

protocol InterviewDraftStoring: AnyObject {
  func load(for workspaceURL: URL, mode: ProjectInterviewMode, schemaVersion: Int) -> InterviewDraftLoadResult
  func loadLegacy(for workspaceURL: URL) -> InterviewDraftLoadResult
  func save(_ draft: InterviewDraft, for workspaceURL: URL) throws
  func delete(for workspaceURL: URL, mode: ProjectInterviewMode, schemaVersion: Int)
  func deleteLegacy(for workspaceURL: URL)
}

final class InterviewDraftStore: InterviewDraftStoring {
  private let directoryURL: URL
  private let fileManager: FileManager

  init(
    directoryURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    self.directoryURL = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("JumaoCat/InterviewDrafts", isDirectory: true)
  }

  func load(for workspaceURL: URL, mode: ProjectInterviewMode, schemaVersion: Int) -> InterviewDraftLoadResult {
    let fileURL = draftURL(for: workspaceURL, mode: mode, schemaVersion: schemaVersion)
    guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }

    do {
      let data = try Data(contentsOf: fileURL)
      let draft = try JSONDecoder().decode(InterviewDraft.self, from: data)
      guard draft.workspaceIdentifier == Self.workspaceIdentifier(for: workspaceURL, mode: mode, schemaVersion: schemaVersion),
            draft.mode == mode,
            draft.schemaVersion == schemaVersion else {
        return .corrupted(reason: "草稿所属项目、问答类型或版本不匹配。")
      }
      return .loaded(draft)
    } catch {
      return .corrupted(reason: Self.corruptionReason(for: error))
    }
  }

  func loadLegacy(for workspaceURL: URL) -> InterviewDraftLoadResult {
    let fileURL = legacyDraftURL(for: workspaceURL)
    guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }

    do {
      let data = try Data(contentsOf: fileURL)
      let draft = try JSONDecoder().decode(InterviewDraft.self, from: data)
      guard draft.workspaceIdentifier == Self.workspaceIdentifier(for: workspaceURL), draft.mode == nil else {
        return .corrupted(reason: "旧草稿所属项目或问答类型不匹配。")
      }
      return .loaded(draft)
    } catch {
      return .corrupted(reason: Self.corruptionReason(for: error))
    }
  }

  func load(for workspaceURL: URL) -> InterviewDraftLoadResult {
    loadLegacy(for: workspaceURL)
  }

  func save(_ draft: InterviewDraft, for workspaceURL: URL) throws {
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let fileURL: URL
    if let mode = draft.mode {
      guard draft.workspaceIdentifier == Self.workspaceIdentifier(
        for: workspaceURL,
        mode: mode,
        schemaVersion: draft.schemaVersion
      ) else {
        throw CocoaError(.fileWriteInvalidFileName)
      }
      fileURL = draftURL(for: workspaceURL, mode: mode, schemaVersion: draft.schemaVersion)
    } else {
      guard draft.workspaceIdentifier == Self.workspaceIdentifier(for: workspaceURL) else {
        throw CocoaError(.fileWriteInvalidFileName)
      }
      fileURL = legacyDraftURL(for: workspaceURL)
    }
    let data = try JSONEncoder().encode(draft)
    try data.write(to: fileURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }

  func delete(for workspaceURL: URL, mode: ProjectInterviewMode, schemaVersion: Int) {
    try? fileManager.removeItem(at: draftURL(for: workspaceURL, mode: mode, schemaVersion: schemaVersion))
  }

  func deleteLegacy(for workspaceURL: URL) {
    try? fileManager.removeItem(at: legacyDraftURL(for: workspaceURL))
  }

  func delete(for workspaceURL: URL) {
    deleteLegacy(for: workspaceURL)
  }

  static func workspaceIdentifier(for workspaceURL: URL) -> String {
    canonicalWorkspacePath(for: workspaceURL)
  }

  static func workspaceIdentifier(
    for workspaceURL: URL,
    mode: ProjectInterviewMode,
    schemaVersion: Int
  ) -> String {
    "\(canonicalWorkspacePath(for: workspaceURL))\u{1F}\(mode.rawValue)\u{1F}\(schemaVersion)"
  }

  private static func canonicalWorkspacePath(for workspaceURL: URL) -> String {
    workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private static func filename(for identifier: String) -> String {
    let digest = SHA256.hash(data: Data(identifier.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func corruptionReason(for error: Error) -> String {
    guard let decodingError = error as? DecodingError else {
      return "草稿文件无法解析。"
    }

    switch decodingError {
    case .dataCorrupted:
      return "草稿文件不是有效的 JSON。"
    case .keyNotFound:
      return "草稿缺少必需内容。"
    case .typeMismatch:
      return "草稿字段格式不正确。"
    case .valueNotFound:
      return "草稿包含空的必需内容。"
    @unknown default:
      return "草稿文件无法解析。"
    }
  }

  func draftURL(for workspaceURL: URL) -> URL {
    legacyDraftURL(for: workspaceURL)
  }

  func draftURL(for workspaceURL: URL, mode: ProjectInterviewMode, schemaVersion: Int) -> URL {
    directoryURL.appendingPathComponent(
      "\(Self.filename(for: Self.workspaceIdentifier(for: workspaceURL, mode: mode, schemaVersion: schemaVersion))).json"
    )
  }

  private func legacyDraftURL(for workspaceURL: URL) -> URL {
    directoryURL.appendingPathComponent("\(Self.filename(for: Self.workspaceIdentifier(for: workspaceURL))).json")
  }
}
