import Foundation

/// Deterministic guard shared by asynchronous trace producers.
public enum TracePersistenceGate {
  public static func permits<Token: Equatable>(
    capturedToken: Token,
    activeToken: Token?,
    isCancelled: Bool
  ) -> Bool {
    !isCancelled && activeToken == capturedToken
  }
}
