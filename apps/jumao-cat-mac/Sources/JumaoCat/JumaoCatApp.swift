import SwiftUI

@main
struct JumaoCatApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
    .commands {
      TextEditingCommands()
    }
  }
}
