import Foundation

/// AI 执行完成后写入项目的完成回执（.jumao/completion-receipt.json）在界面上的阶段表达。
/// 文案与 CLI 的 completionReceiptStage 保持同一套人话，遵循「X。不是 Y。」防误读句式。
struct CompletionReceiptStage: Equatable {
  enum Kind: String {
    case completed = "receipt_completed"
    case blocked = "receipt_blocked"
    case invalid = "receipt_invalid"
  }

  let kind: Kind
  let message: String
  let nextStep: String
  let completedGoalIds: [String]
  let blockedReasons: [String]

  static let receiptRelativePath = ".jumao/completion-receipt.json"

  static func load(workspaceURL: URL) -> CompletionReceiptStage? {
    let url = workspaceURL.appendingPathComponent(receiptRelativePath)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return parse(data: data)
  }

  static func parse(data: Data) -> CompletionReceiptStage {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      return invalidStage()
    }
    let body = (object["jumaoCompletion"] as? [String: Any]) ?? object
    guard let status = body["status"] as? String,
          status == "completed" || status == "blocked",
          let goalsCompleted = body["goalsCompleted"] as? [Any],
          let goalsBlocked = body["goalsBlocked"] as? [Any],
          body["validation"] is [Any],
          body["productionEffects"] is Bool,
          body["remainingWork"] is [Any] else {
      return invalidStage()
    }

    let blockedReasons: [String] = goalsBlocked.compactMap { entry in
      if let text = entry as? String { return text }
      if let dictionary = entry as? [String: Any] {
        let goal = dictionary["goalId"] as? String ?? "未知目标"
        if let reason = dictionary["reason"] as? String, !reason.isEmpty {
          return "\(goal)：\(reason)"
        }
        return goal
      }
      return nil
    }
    let completedIds = goalsCompleted.compactMap { $0 as? String }

    if status == "blocked" || !blockedReasons.isEmpty {
      return CompletionReceiptStage(
        kind: .blocked,
        message: "AI 交回执说有些目标没做完，原因写在回执里。不是失败。",
        nextStep: "看看回执里被卡住的原因，补上信息后再让 AI 继续。",
        completedGoalIds: completedIds,
        blockedReasons: blockedReasons
      )
    }
    return CompletionReceiptStage(
      kind: .completed,
      message: "AI 交回执说这次的活做完了。不是橘猫核验过的结论。",
      nextStep: "对照回执里列的目标，自己点一点功能，确认真的做完了。",
      completedGoalIds: completedIds,
      blockedReasons: []
    )
  }

  private static func invalidStage() -> CompletionReceiptStage {
    CompletionReceiptStage(
      kind: .invalid,
      message: "AI 交了一份回执，但内容不完整或格式不对。不是项目失败。",
      nextStep: "让 AI 重新交一份完整回执，或重新跑一次这项工作。",
      completedGoalIds: [],
      blockedReasons: []
    )
  }
}
