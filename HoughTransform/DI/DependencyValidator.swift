import Foundation
import Metal

enum DependencyError: Error, LocalizedError {
  case metalNotSupported
  case commandQueueCreationFailed
  case libraryNotFound
  
  var errorDescription: String? {
    switch self {
    case .metalNotSupported:
      return "Metal is not supported on this device. This app requires Metal to run."
    case .commandQueueCreationFailed:
      return "Failed to initialize commandQueue. Please restart the app."
    case .libraryNotFound:
      return "Failed to initialize library"
    }
  }
  
  var recoverySuggestion: String? {
    switch self {
    case .metalNotSupported:
      return "This app requires a device with Metal support (iOS 13+ or macOS 10.15+)."
    case .commandQueueCreationFailed:
      return "Try restarting the app. If the problem persists, please contact support."
    case .libraryNotFound:
      return "Try restarting your device."
    }
  }
}

@MainActor
final class DependencyValidator {
  static let shared = DependencyValidator()
  
  private(set) var isValid = false
  private(set) var validationError: DependencyError?
  
  private init() {}
  
  func validate() -> Result<Void, DependencyError> {
    guard let device = MTLCreateSystemDefaultDevice() else {
      validationError = .metalNotSupported
      return .failure(.metalNotSupported)
    }
    
    guard device.makeCommandQueue() != nil else {
      validationError = .commandQueueCreationFailed
      return .failure(.commandQueueCreationFailed)
    }
    
    guard device.makeDefaultLibrary() != nil else {
      validationError = .libraryNotFound
      return .failure(.libraryNotFound)
    }
    
    isValid = true
    return .success(())
  }
  
  func reset() {
    isValid = false
    validationError = nil
  }
}
