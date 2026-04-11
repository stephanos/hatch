import Darwin
import Foundation

extension FileHandle {
  var isTTY: Bool {
    isatty(fileDescriptor) != 0
  }
}
