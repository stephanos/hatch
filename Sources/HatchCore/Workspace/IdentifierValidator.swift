import Foundation

public enum IdentifierValidator {
  public static func validate(label: String, value: String) throws -> String {
    let trimmed = trimmed(value)
    guard !trimmed.isEmpty else {
      throw HatchError.message("\(label) cannot be empty")
    }
    guard isValid(trimmed) else {
      throw HatchError.message("\(label) must match [a-zA-Z0-9_-]+")
    }
    return trimmed
  }

  public static func validationError(label: String, value: String) -> String? {
    let trimmed = trimmed(value)
    guard !trimmed.isEmpty else {
      return nil
    }
    guard !trimmed.contains(where: \.isWhitespace) else {
      return "\(label) cannot contain spaces."
    }
    guard isValid(trimmed) else {
      return "\(label) must match [a-zA-Z0-9_-]+."
    }
    return nil
  }

  private static func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isValid(_ value: String) -> Bool {
    value.unicodeScalars.allSatisfy { scalar in
      CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
    }
  }
}
