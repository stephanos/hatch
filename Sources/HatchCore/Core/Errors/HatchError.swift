import Foundation

public enum HatchError: LocalizedError, Identifiable, Sendable {
  case message(String)

  public var id: String { errorDescription ?? UUID().uuidString }

  public var errorDescription: String? {
    switch self {
    case .message(let message):
      return message
    }
  }
}
