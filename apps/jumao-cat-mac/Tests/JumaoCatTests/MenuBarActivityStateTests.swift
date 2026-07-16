import XCTest
@testable import JumaoCat

@MainActor
final class MenuBarActivityStateTests: XCTestCase {
  func testOperationShowsWorkingThenSuccessAndReturnsToIdle() {
    let coordinator = MenuBarActivityCoordinator()

    let operationID = coordinator.beginOperation()
    XCTAssertEqual(coordinator.state, .working)

    coordinator.finishOperation(operationID, result: .success)
    XCTAssertEqual(coordinator.state, .success)

    coordinator.completeTransientFeedback()
    XCTAssertEqual(coordinator.state, .idle)
  }

  func testFailureStaysBlockedUntilNextRealOperation() {
    let coordinator = MenuBarActivityCoordinator()
    let operationID = coordinator.beginOperation()

    coordinator.finishOperation(operationID, result: .failure)
    XCTAssertEqual(coordinator.state, .failure)

    _ = coordinator.beginOperation()
    XCTAssertEqual(coordinator.state, .working)
  }

  func testCopiedReturnsToPreviousIdleState() {
    let coordinator = MenuBarActivityCoordinator()

    coordinator.showCopied()
    XCTAssertEqual(coordinator.state, .copied)

    coordinator.completeTransientFeedback()
    XCTAssertEqual(coordinator.state, .idle)
  }

  func testOverlappingOperationsDoNotLeaveWorkingEarly() {
    let coordinator = MenuBarActivityCoordinator()
    let firstOperation = coordinator.beginOperation()
    let secondOperation = coordinator.beginOperation()

    coordinator.finishOperation(firstOperation, result: .success)
    XCTAssertEqual(coordinator.state, .working)

    coordinator.finishOperation(secondOperation, result: .success)
    XCTAssertEqual(coordinator.state, .success)
  }

  func testOverlappingFailureIsNotLostWhenAnotherOperationStarts() {
    let coordinator = MenuBarActivityCoordinator()
    let firstOperation = coordinator.beginOperation()
    let secondOperation = coordinator.beginOperation()

    coordinator.finishOperation(firstOperation, result: .failure)
    let thirdOperation = coordinator.beginOperation()
    coordinator.finishOperation(secondOperation, result: .success)
    XCTAssertEqual(coordinator.state, .working)

    coordinator.finishOperation(thirdOperation, result: .success)
    XCTAssertEqual(coordinator.state, .failure)
  }

  func testNewOperationCancelsPriorSuccessFeedback() {
    let coordinator = MenuBarActivityCoordinator()
    let operationID = coordinator.beginOperation()
    coordinator.finishOperation(operationID, result: .success)

    let nextOperationID = coordinator.beginOperation()
    coordinator.completeTransientFeedback()

    XCTAssertEqual(coordinator.state, .working)
    coordinator.cancelOperation(nextOperationID)
    XCTAssertEqual(coordinator.state, .idle)
  }

  func testResetCancelsAllActivityForAppTermination() {
    let coordinator = MenuBarActivityCoordinator()
    _ = coordinator.beginOperation()

    coordinator.reset()

    XCTAssertEqual(coordinator.state, .idle)
    XCTAssertFalse(coordinator.hasActiveOperations)
  }

  func testReduceMotionUsesStaticIconForEveryActivity() {
    for activity in [
      MenuBarActivityState.idle,
      .working,
      .success,
      .failure,
      .copied
    ] {
      XCTAssertEqual(
        MenuBarCatAnimator.animationKind(for: activity, reduceMotion: true),
        .none
      )
    }
  }

  func testWorkingUsesOnlyBreathingAnimationWithoutReduceMotion() {
    XCTAssertEqual(
      MenuBarCatAnimator.animationKind(for: .working, reduceMotion: false),
      .breathing
    )
  }

  func testIdleDefaultsToRestingCatAndHoverUsesAwakeCat() {
    XCTAssertEqual(
      MenuBarCatAnimator.visualState(activity: .idle, persistentState: "ready", isHovered: false),
      .idleRest
    )
    XCTAssertEqual(
      MenuBarCatAnimator.visualState(activity: .idle, persistentState: "ready", isHovered: true),
      .idleAwake
    )
  }

  func testWorkingAndBlockedAreNeverOverriddenByHover() {
    XCTAssertEqual(
      MenuBarCatAnimator.visualState(activity: .working, persistentState: "ready", isHovered: true),
      .working
    )
    XCTAssertEqual(
      MenuBarCatAnimator.visualState(activity: .working, persistentState: "blocked", isHovered: true),
      .blocked
    )
    XCTAssertEqual(
      MenuBarCatAnimator.visualState(activity: .failure, persistentState: "ready", isHovered: true),
      .blocked
    )
  }

  func testSuccessAndCopiedAreNeverInterruptedByHover() {
    XCTAssertEqual(
      MenuBarCatAnimator.visualState(activity: .success, persistentState: "ready", isHovered: true),
      .success
    )
    XCTAssertEqual(
      MenuBarCatAnimator.visualState(activity: .copied, persistentState: "ready", isHovered: true),
      .copied
    )
  }

  func testIdleTransitionUsesApprovedWakeAndRestFrames() {
    XCTAssertEqual(
      MenuBarCatAnimator.idleTransitionIconStates(isHovered: true, reduceMotion: false),
      ["idleWaking01", "idleWaking02", "idleAwake"]
    )
    XCTAssertEqual(
      MenuBarCatAnimator.idleTransitionIconStates(isHovered: false, reduceMotion: false),
      ["idleResting01", "idleResting02", "idleRest"]
    )
  }

  func testReduceMotionSwitchesIdleIconsWithoutTransitionFrames() {
    XCTAssertEqual(
      MenuBarCatAnimator.idleTransitionIconStates(isHovered: true, reduceMotion: true),
      ["idleAwake"]
    )
    XCTAssertEqual(
      MenuBarCatAnimator.idleTransitionIconStates(isHovered: false, reduceMotion: true),
      ["idleRest"]
    )

    let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    let animator = MenuBarCatAnimator(button: button)
    animator.render(activity: .idle, persistentState: "ready", reduceMotion: true)
    animator.setHovered(true)

    XCTAssertEqual(animator.renderedIconState, "idleAwake")
    XCTAssertFalse(animator.hasActiveAnimationTask)

    animator.setHovered(false)
    XCTAssertEqual(animator.renderedIconState, "idleRest")
    XCTAssertFalse(animator.hasActiveAnimationTask)
  }

  func testNewActivityCancelsIdleTransitionAndStopCleansEveryTask() {
    let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    let animator = MenuBarCatAnimator(button: button)
    animator.render(activity: .idle, persistentState: "ready", reduceMotion: false)
    animator.setHovered(true)

    XCTAssertEqual(animator.renderedIconState, "idleWaking01")
    XCTAssertTrue(animator.hasActiveAnimationTask)

    animator.render(activity: .working, persistentState: "ready", reduceMotion: false)
    XCTAssertEqual(animator.renderedIconState, "checking")
    XCTAssertTrue(animator.hasActiveAnimationTask)

    animator.stop()
    XCTAssertNil(animator.renderedIconState)
    XCTAssertFalse(animator.hasActiveAnimationTask)
  }

  func testRapidHoverChangesReplaceThePreviousTransition() {
    let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    let animator = MenuBarCatAnimator(button: button)
    animator.render(activity: .idle, persistentState: "ready", reduceMotion: false)

    animator.setHovered(true)
    animator.setHovered(false)
    animator.setHovered(true)

    XCTAssertEqual(animator.renderedIconState, "idleWaking01")
    XCTAssertTrue(animator.hasActiveAnimationTask)
    animator.stop()
  }

  func testHoverTrackerUsesButtonTrackingAreaAndDoesNotChangeClickAction() {
    let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    let action = #selector(MenuBarHoverActionTarget.performAction(_:))
    let target = MenuBarHoverActionTarget()
    button.target = target
    button.action = action

    let tracker = MenuBarHoverTracker(button: button)
    tracker.start()

    let trackingAreas = button.trackingAreas.filter {
      $0.options.contains(.mouseEnteredAndExited)
        && $0.options.contains(.activeAlways)
        && $0.options.contains(.inVisibleRect)
        && $0.owner === tracker
    }
    XCTAssertEqual(trackingAreas.count, 1)
    XCTAssertTrue(button.target === target)
    XCTAssertEqual(button.action, action)

    var hoverChanges: [Bool] = []
    tracker.onHoverChange = { hoverChanges.append($0) }
    tracker.updateHover(true)
    tracker.updateHover(false)
    XCTAssertEqual(hoverChanges, [true, false])

    tracker.stop()
    XCTAssertFalse(button.trackingAreas.contains { $0.owner === tracker })
  }
}

@MainActor
private final class MenuBarHoverActionTarget: NSObject {
  @objc func performAction(_ sender: Any?) {}
}
