public struct CLIError: Error {
  public let message: String

  public init(message: String) {
    self.message = message
  }
}
