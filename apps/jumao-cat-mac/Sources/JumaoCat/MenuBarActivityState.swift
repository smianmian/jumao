import Foundation

enum MenuBarActivityState: Equatable, Sendable {
  case idle
  case working
  case success
  case failure
  case copied
}

enum MenuBarOperationResult: Sendable {
  case success
  case failure
}

@MainActor
final class MenuBarActivityCoordinator {
  private(set) var state: MenuBarActivityState = .idle {
    didSet {
      guard oldValue != state else { return }
      onStateChange?(state)
    }
  }

  var onStateChange: ((MenuBarActivityState) -> Void)?

  private var activeOperationIDs = Set<UUID>()
  private var pendingResult: MenuBarOperationResult?
  private var feedbackTask: Task<Void, Never>?

  var hasActiveOperations: Bool {
    !activeOperationIDs.isEmpty
  }

  func beginOperation() -> UUID {
    feedbackTask?.cancel()
    feedbackTask = nil
    if activeOperationIDs.isEmpty {
      pendingResult = nil
    }

    let operationID = UUID()
    activeOperationIDs.insert(operationID)
    state = .working
    return operationID
  }

  func finishOperation(_ operationID: UUID, result: MenuBarOperationResult) {
    guard activeOperationIDs.remove(operationID) != nil else { return }

    if !activeOperationIDs.isEmpty {
      if result == .failure || pendingResult == nil {
        pendingResult = result
      }
      return
    }

    let finalResult = pendingResult ?? result
    pendingResult = nil

    switch finalResult {
    case .success:
      showTransient(.success, duration: 800_000_000)
    case .failure:
      state = .failure
    }
  }

  func cancelOperation(_ operationID: UUID) {
    guard activeOperationIDs.remove(operationID) != nil else { return }
    guard activeOperationIDs.isEmpty else { return }
    pendingResult = nil
    state = .idle
  }

  func showCopied() {
    guard activeOperationIDs.isEmpty else { return }
    showTransient(.copied, duration: 1_200_000_000)
  }

  func reset() {
    feedbackTask?.cancel()
    feedbackTask = nil
    activeOperationIDs.removeAll()
    pendingResult = nil
    state = .idle
  }

  func completeTransientFeedback() {
    guard state == .success || state == .copied else { return }
    feedbackTask?.cancel()
    feedbackTask = nil
    state = activeOperationIDs.isEmpty ? .idle : .working
  }

  private func showTransient(_ transientState: MenuBarActivityState, duration: UInt64) {
    feedbackTask?.cancel()
    feedbackTask = nil
    state = transientState

    feedbackTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: duration)
      guard !Task.isCancelled else { return }
      self?.completeTransientFeedback()
    }
  }
}
