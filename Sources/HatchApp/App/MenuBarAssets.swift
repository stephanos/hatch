import AppKit
import SwiftUI

enum MenuBarAssets {
  private static let resourceBundleName = "hatch_hatch.bundle"

  static let statusImage: NSImage =
    loadTwemojiImage(
      named: "twemoji-hatching-chick",
      size: NSSize(width: 18, height: 18)
    )
    ?? fallbackBrandMarkImage(
      size: NSSize(width: 18, height: 18),
      strokeColor: .labelColor,
      fillColor: .clear,
      isTemplate: true
    )

  static let headerImage: NSImage =
    loadTwemojiImage(
      named: "twemoji-hatching-chick",
      size: NSSize(width: 30, height: 30)
    )
    ?? fallbackBrandMarkImage(
      size: NSSize(width: 30, height: 30),
      strokeColor: NSColor(calibratedWhite: 0.16, alpha: 1.0),
      fillColor: NSColor(calibratedWhite: 1.0, alpha: 0.88),
      isTemplate: false
    )

  static let spotlightImage: NSImage =
    loadTwemojiImage(
      named: "twemoji-hatching-chick",
      size: NSSize(width: 22, height: 22)
    )
    ?? brandMarkImage(
      size: NSSize(width: 22, height: 22),
      strokeColor: NSColor(calibratedWhite: 0.2, alpha: 1.0),
      fillColor: NSColor(calibratedWhite: 1.0, alpha: 0.16),
      isTemplate: false
    )

  static let configurationImage: NSImage =
    loadTwemojiImage(
      named: "twemoji-hatching-chick",
      size: NSSize(width: 30, height: 30)
    )
    ?? brandMarkImage(
      size: NSSize(width: 30, height: 30),
      strokeColor: NSColor(calibratedWhite: 0.16, alpha: 1.0),
      fillColor: NSColor(calibratedWhite: 1.0, alpha: 0.88),
      isTemplate: false
    )

  private static func loadTwemojiImage(named name: String, size: NSSize) -> NSImage? {
    guard
      let url = resourceURL(forResource: name, withExtension: "png"),
      let image = NSImage(contentsOf: url)
    else {
      return nil
    }

    image.size = size
    image.isTemplate = false
    return image
  }

  private static func resourceURL(forResource name: String, withExtension ext: String) -> URL? {
    for bundle in resourceBundles() {
      if let url = bundle.url(forResource: name, withExtension: ext) {
        return url
      }
    }

    let filename = "\(name).\(ext)"
    for directory in candidateDirectories() {
      let directURL = directory.appendingPathComponent(filename)
      if FileManager.default.fileExists(atPath: directURL.path) {
        return directURL
      }

      let bundledURL =
        directory
        .appendingPathComponent(resourceBundleName)
        .appendingPathComponent(filename)
      if FileManager.default.fileExists(atPath: bundledURL.path) {
        return bundledURL
      }
    }

    return nil
  }

  private static func resourceBundles() -> [Bundle] {
    var bundles = [Bundle.main]
    for directory in candidateDirectories() {
      let bundleURL = directory.appendingPathComponent(resourceBundleName)
      if let bundle = Bundle(url: bundleURL) {
        bundles.append(bundle)
      }
    }
    return bundles
  }

  private static func candidateDirectories() -> [URL] {
    let directories = [
      Bundle.main.resourceURL,
      Bundle.main.bundleURL,
      Bundle.main.executableURL?.deletingLastPathComponent(),
    ]

    var seen = Set<String>()
    return directories.compactMap { url in
      guard let url else { return nil }
      let path = url.standardizedFileURL.path
      guard seen.insert(path).inserted else {
        return nil
      }
      return url
    }
  }

  private static func fallbackBrandMarkImage(
    size: NSSize,
    strokeColor: NSColor,
    fillColor: NSColor,
    isTemplate: Bool
  ) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    NSBezierPath(rect: rect).fill()

    let width = size.width
    let height = size.height
    let lineWidth = max(1.25, round(width * 0.075))

    let eggRect = NSRect(
      x: width * 0.18,
      y: height * 0.14,
      width: width * 0.64,
      height: height * 0.72
    )

    let egg = NSBezierPath(roundedRect: eggRect, xRadius: width * 0.33, yRadius: height * 0.42)
    fillColor.setFill()
    egg.fill()
    strokeColor.setStroke()
    egg.lineWidth = lineWidth
    egg.stroke()

    let crack = NSBezierPath()
    crack.move(to: NSPoint(x: width * 0.28, y: height * 0.47))
    crack.line(to: NSPoint(x: width * 0.38, y: height * 0.54))
    crack.line(to: NSPoint(x: width * 0.47, y: height * 0.43))
    crack.line(to: NSPoint(x: width * 0.56, y: height * 0.53))
    crack.line(to: NSPoint(x: width * 0.67, y: height * 0.45))
    crack.lineWidth = lineWidth
    crack.lineCapStyle = .round
    crack.lineJoinStyle = .round
    strokeColor.setStroke()
    crack.stroke()

    let hatch = NSBezierPath()
    hatch.move(to: NSPoint(x: width * 0.34, y: height * 0.25))
    hatch.line(to: NSPoint(x: width * 0.66, y: height * 0.25))
    hatch.lineWidth = lineWidth
    hatch.lineCapStyle = .round
    hatch.stroke()

    image.unlockFocus()
    image.isTemplate = isTemplate
    return image
  }

  private static func brandMarkImage(
    size: NSSize,
    strokeColor: NSColor,
    fillColor: NSColor,
    isTemplate: Bool
  ) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    NSBezierPath(rect: rect).fill()

    let width = size.width
    let height = size.height
    let lineWidth = max(1.35, round(width * 0.09))
    let inset = max(2.5, round(width * 0.14))
    let shellRect = NSRect(
      x: inset,
      y: inset,
      width: width - (inset * 2),
      height: height - (inset * 2)
    )

    let shell = NSBezierPath(roundedRect: shellRect, xRadius: width * 0.16, yRadius: height * 0.16)
    fillColor.setFill()
    shell.fill()
    strokeColor.setStroke()
    shell.lineWidth = lineWidth
    shell.stroke()

    let leftRail = width * 0.34
    let rightRail = width * 0.66
    let top = height * 0.72
    let bottom = height * 0.28

    let rails = NSBezierPath()
    rails.move(to: NSPoint(x: leftRail, y: bottom))
    rails.line(to: NSPoint(x: leftRail, y: top))
    rails.move(to: NSPoint(x: rightRail, y: bottom))
    rails.line(to: NSPoint(x: rightRail, y: top))
    rails.lineWidth = lineWidth
    rails.lineCapStyle = .round
    rails.stroke()

    let crossbar = NSBezierPath()
    crossbar.move(to: NSPoint(x: leftRail, y: height * 0.5))
    crossbar.line(to: NSPoint(x: rightRail, y: height * 0.5))
    crossbar.lineWidth = lineWidth
    crossbar.lineCapStyle = .round
    crossbar.stroke()

    image.unlockFocus()
    image.isTemplate = isTemplate
    return image
  }
}
