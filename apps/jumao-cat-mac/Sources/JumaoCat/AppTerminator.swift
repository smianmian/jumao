import AppKit

@MainActor
protocol AppTerminating {
  func terminate()
}

@MainActor
final class MacAppTerminator: AppTerminating {
  func terminate() {
    NSApplication.shared.terminate(nil)
  }
}
