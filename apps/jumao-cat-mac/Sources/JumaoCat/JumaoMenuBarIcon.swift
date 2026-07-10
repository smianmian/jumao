import AppKit

enum JumaoMenuBarIcon {
  static func makeImage(for state: String) -> NSImage {
    let assetName = assetName(for: state)

    guard let image = NSImage(named: NSImage.Name(assetName)) else {
      return NSImage(systemSymbolName: "cat", accessibilityDescription: "Jumao Cat") ?? NSImage()
    }

    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    return image
  }

  static func assetName(for state: String) -> String {
    switch state {
    case "ready":
      return "JumaoReadyTemplate"
    case "checking":
      return "JumaoCheckingTemplate"
    case "blocked":
      return "JumaoBlockedTemplate"
    case "packed":
      return "JumaoPackedTemplate"
    default:
      return "JumaoSleepingTemplate"
    }
  }
}
