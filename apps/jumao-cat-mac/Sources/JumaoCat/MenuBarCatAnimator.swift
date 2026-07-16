import AppKit
import QuartzCore

enum MenuBarCatAnimationKind: Equatable {
  case none
  case breathing
  case success
  case failure
  case copied
}

enum MenuBarCatVisualState: Equatable {
  case blocked
  case working
  case success
  case copied
  case idleRest
  case idleAwake
}

@MainActor
final class MenuBarCatAnimator {
  private struct RenderState: Equatable {
    let visualState: MenuBarCatVisualState
    let animationKind: MenuBarCatAnimationKind
  }

  private weak var button: NSStatusBarButton?
  private var breathingTask: Task<Void, Never>?
  private var idleTransitionTask: Task<Void, Never>?
  private var renderState: RenderState?
  private var activity: MenuBarActivityState = .idle
  private var persistentState = "sleeping"
  private var reduceMotion = false
  private(set) var isHovered = false
  private(set) var renderedIconState: String?

  var hasActiveAnimationTask: Bool {
    breathingTask != nil || idleTransitionTask != nil
  }

  init(button: NSStatusBarButton) {
    self.button = button
    button.wantsLayer = true
  }

  func render(
    activity: MenuBarActivityState,
    persistentState: String,
    reduceMotion: Bool
  ) {
    self.activity = activity
    self.persistentState = persistentState
    self.reduceMotion = reduceMotion
    renderCurrentState()
  }

  func setHovered(_ isHovered: Bool) {
    guard self.isHovered != isHovered else { return }
    self.isHovered = isHovered
    renderCurrentState()
  }

  private func renderCurrentState() {
    guard button != nil else { return }

    let visualState = Self.visualState(
      activity: activity,
      persistentState: persistentState,
      isHovered: isHovered
    )
    let animationKind = Self.animationKind(
      for: visualState,
      activity: activity,
      reduceMotion: reduceMotion
    )
    let nextState = RenderState(visualState: visualState, animationKind: animationKind)
    guard renderState != nextState else { return }

    let previousVisualState = renderState?.visualState
    stopAnimations(resetImage: false)
    renderState = nextState

    if visualState == .idleRest || visualState == .idleAwake {
      renderIdleState(visualState, previousVisualState: previousVisualState)
      return
    }

    setIcon(Self.iconState(for: visualState))
    switch animationKind {
    case .none:
      break
    case .breathing:
      startBreathing()
    case .success:
      addKeyframeAnimation(
        key: "jumao.success",
        keyPath: "transform.translation.y",
        values: [0, -1, 0],
        keyTimes: [0, 0.45, 1],
        duration: 0.55
      )
    case .failure:
      addKeyframeAnimation(
        key: "jumao.failure",
        keyPath: "transform.translation.x",
        values: [0, -1, 1, -1, 1, 0],
        keyTimes: [0, 0.18, 0.36, 0.54, 0.72, 1],
        duration: 0.7
      )
    case .copied:
      addKeyframeAnimation(
        key: "jumao.copied",
        keyPath: "transform.translation.y",
        values: [0, -1, 0, -1, 0],
        keyTimes: [0, 0.2, 0.45, 0.68, 1],
        duration: 0.75
      )
    }
  }

  func stop() {
    stopAnimations(resetImage: true)
    renderState = nil
  }

  static func animationKind(
    for activity: MenuBarActivityState,
    reduceMotion: Bool
  ) -> MenuBarCatAnimationKind {
    guard !reduceMotion else { return .none }
    switch activity {
    case .idle: return .none
    case .working: return .breathing
    case .success: return .success
    case .failure: return .failure
    case .copied: return .copied
    }
  }

  static func visualState(
    activity: MenuBarActivityState,
    persistentState: String,
    isHovered: Bool
  ) -> MenuBarCatVisualState {
    if activity == .failure || persistentState == "blocked" {
      return .blocked
    }
    switch activity {
    case .working: return .working
    case .success: return .success
    case .copied: return .copied
    case .idle: return isHovered ? .idleAwake : .idleRest
    case .failure: return .blocked
    }
  }

  static func idleTransitionIconStates(isHovered: Bool, reduceMotion: Bool) -> [String] {
    if reduceMotion {
      return [isHovered ? "idleAwake" : "idleRest"]
    }
    return isHovered
      ? ["idleWaking01", "idleWaking02", "idleAwake"]
      : ["idleResting01", "idleResting02", "idleRest"]
  }

  private static func iconState(for visualState: MenuBarCatVisualState) -> String {
    switch visualState {
    case .blocked: return "blocked"
    case .working: return "checking"
    case .success: return "ready"
    case .copied: return "copied"
    case .idleRest: return "idleRest"
    case .idleAwake: return "idleAwake"
    }
  }

  private static func animationKind(
    for visualState: MenuBarCatVisualState,
    activity: MenuBarActivityState,
    reduceMotion: Bool
  ) -> MenuBarCatAnimationKind {
    guard !reduceMotion else { return .none }
    switch visualState {
    case .blocked: return activity == .failure ? .failure : .none
    case .working: return .breathing
    case .success: return .success
    case .copied: return .copied
    case .idleRest, .idleAwake: return .none
    }
  }

  private func renderIdleState(
    _ visualState: MenuBarCatVisualState,
    previousVisualState: MenuBarCatVisualState?
  ) {
    let shouldAnimateTransition = !reduceMotion && (
      (visualState == .idleAwake && previousVisualState == .idleRest)
        || (visualState == .idleRest && previousVisualState == .idleAwake)
    )
    guard shouldAnimateTransition else {
      setIcon(Self.iconState(for: visualState))
      return
    }

    startIdleTransition(
      iconStates: Self.idleTransitionIconStates(
        isHovered: visualState == .idleAwake,
        reduceMotion: false
      )
    )
  }

  private func startIdleTransition(iconStates: [String]) {
    guard let firstIconState = iconStates.first else { return }
    setIcon(firstIconState)

    idleTransitionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for iconState in iconStates.dropFirst() {
        try? await Task.sleep(nanoseconds: 160_000_000)
        guard !Task.isCancelled else { return }
        self.setIcon(iconState)
      }
      self.idleTransitionTask = nil
    }
  }

  private func setIcon(_ iconState: String) {
    button?.image = JumaoMenuBarIcon.makeImage(for: iconState)
    renderedIconState = iconState
  }

  private func startBreathing() {
    breathingTask = Task { @MainActor [weak self] in
      guard let self else { return }

      while !Task.isCancelled {
        self.animateOpacity(to: 0.45, duration: 0.4)
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }

        self.animateOpacity(to: 1, duration: 0.4)
        try? await Task.sleep(nanoseconds: 400_000_000)
      }
    }
  }

  private func animateOpacity(to value: CGFloat, duration: TimeInterval) {
    guard let button else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      button.animator().alphaValue = value
    }
  }

  private func addKeyframeAnimation(
    key: String,
    keyPath: String,
    values: [NSNumber],
    keyTimes: [NSNumber],
    duration: CFTimeInterval
  ) {
    guard let layer = button?.layer else { return }

    let animation = CAKeyframeAnimation(keyPath: keyPath)
    animation.values = values
    animation.keyTimes = keyTimes
    animation.duration = duration
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: key)
  }

  private func stopAnimations(resetImage: Bool) {
    breathingTask?.cancel()
    breathingTask = nil
    idleTransitionTask?.cancel()
    idleTransitionTask = nil
    button?.layer?.removeAllAnimations()
    button?.alphaValue = 1

    if resetImage {
      button?.image = nil
      renderedIconState = nil
    }
  }
}

@MainActor
final class MenuBarHoverTracker: NSObject {
  private weak var button: NSStatusBarButton?
  private var trackingArea: NSTrackingArea?
  private(set) var isHovered = false
  var onHoverChange: ((Bool) -> Void)?

  init(button: NSStatusBarButton) {
    self.button = button
    super.init()
    start()
  }

  func start() {
    stopTracking()
    guard let button else { return }
    let trackingArea = NSTrackingArea(
      rect: button.bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    button.addTrackingArea(trackingArea)
    self.trackingArea = trackingArea
  }

  func stop() {
    stopTracking()
    updateHover(false)
    onHoverChange = nil
  }

  @objc func mouseEntered(with event: NSEvent) {
    updateHover(true)
  }

  @objc func mouseExited(with event: NSEvent) {
    updateHover(false)
  }

  func updateHover(_ isHovered: Bool) {
    guard self.isHovered != isHovered else { return }
    self.isHovered = isHovered
    onHoverChange?(isHovered)
  }

  private func stopTracking() {
    guard let button, let trackingArea else { return }
    button.removeTrackingArea(trackingArea)
    self.trackingArea = nil
  }
}
