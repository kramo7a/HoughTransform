import SwiftUI

@MainActor
@Observable
final class AppState {
  var isValidated = false
  var validationError: DependencyError?
  
  func validateDependencies() {
    let result = DependencyValidator.shared.validate()
    
    switch result {
    case .success:
      isValidated = true
      validationError = nil
    case .failure(let error):
      isValidated = false
      validationError = error
    }
  }
}

@main
struct HoughTransformApp: App {
  @State private var appState = AppState()
  
  var body: some Scene {
    WindowGroup {
      Group {
        if let error = appState.validationError {
          ErrorView(error: error)
        } else if appState.isValidated {
          ContentView()
#if !os(iOS)
            .frame(minWidth: 1300, minHeight: 600)
#endif
        } else {
          ProgressView("Initializing...")
        }
      }
      .task {
        appState.validateDependencies()
      }
    }
#if os(visionOS)
    .windowStyle(.plain)
#endif
#if os(macOS)
    .windowResizability(.contentSize)
#endif
  }
}

struct ErrorView: View {
  let error: DependencyError
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 20) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 60))
          .foregroundStyle(.red)
        
        Text("Initialization Error")
          .font(.title)
          .fontWeight(.bold)
        
        if let description = error.errorDescription {
          Text(description)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
        
        if let suggestion = error.recoverySuggestion {
          Text(suggestion)
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
        }
      }
      .padding(40)
      .foregroundStyle(.white)
    }
  }
}
