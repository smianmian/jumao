import AppKit

enum JumaoMenuBarIcon {
  static func makeImage(for state: String) -> NSImage {
    let assetName = assetName(for: state)
    let sourceImage = NSImage(named: NSImage.Name(assetName))
      ?? NSImage(systemSymbolName: "cat", accessibilityDescription: "Jumao Cat")
      ?? NSImage()
    let image = sourceImage.copy() as? NSImage ?? sourceImage
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    return image
  }

  static func makeColorImage() -> NSImage {
    let sourceImage = NSImage(named: NSImage.Name("JumaoCatColor"))
      ?? NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Jumao Cat")
      ?? NSImage()
    let image = sourceImage.copy() as? NSImage ?? sourceImage
    image.isTemplate = false
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
