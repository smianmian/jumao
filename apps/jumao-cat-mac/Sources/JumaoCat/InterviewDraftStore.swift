import CryptoKit
import Foundation

struct InterviewDraft: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let workspaceIdentifier: String
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
    self.currentQuestionIndex = currentQuestionIndex
    self.answers = answers
    self.skippedAnswerPaths = skippedAnswerPaths
    self.isInterviewComplete = isInterviewComplete
    self.stageID = stageID
    self.isCurrentStageComplete = isCurrentStageComplete
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion, workspaceIdentifier, currentQuestionIndex, answers, skippedAnswerPaths, isInterviewComplete, stageID, isCurrentStageComplete, updatedAt
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    workspaceIdentifier = try container.decode(String.self, forKey: .workspaceIdentifier)
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
  case corrupted
}

protocol InterviewDraftStoring: AnyObject {
  func load(for workspaceURL: URL) -> InterviewDraftLoadResult
  func save(_ draft: InterviewDraft, for workspaceURL: URL) throws
  func delete(for workspaceURL: URL)
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

  func load(for workspaceURL: URL) -> InterviewDraftLoadResult {
    let fileURL = draftURL(for: workspaceURL)
    guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }

    do {
      let data = try Data(contentsOf: fileURL)
      let draft = try JSONDecoder().decode(InterviewDraft.self, from: data)
      return draft.workspaceIdentifier == Self.workspaceIdentifier(for: workspaceURL) ? .loaded(draft) : .corrupted
    } catch {
      return .corrupted
    }
  }

  func save(_ draft: InterviewDraft, for workspaceURL: URL) throws {
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let fileURL = draftURL(for: workspaceURL)
    let data = try JSONEncoder().encode(draft)
    try data.write(to: fileURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }

  func delete(for workspaceURL: URL) {
    try? fileManager.removeItem(at: draftURL(for: workspaceURL))
  }

  static func workspaceIdentifier(for workspaceURL: URL) -> String {
    let path = workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path
    let digest = SHA256.hash(data: Data(path.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  func draftURL(for workspaceURL: URL) -> URL {
    directoryURL.appendingPathComponent("\(Self.workspaceIdentifier(for: workspaceURL)).json")
  }
}
