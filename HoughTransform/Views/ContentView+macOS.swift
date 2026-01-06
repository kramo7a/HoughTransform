#if os(macOS)
import SwiftUI
import PhotosUI
import AppKit
import FactoryKit

struct ContentView_macOS: View {
  
  @Injected(\.houghParameters) private var parameters: HoughParameters
  @Injected(\.houghPipeline) private var pipeline: any Pipeline
  @Injected(\.inputTextureSource) private var coordinator: InputTextureSource
  
  @Binding var selectedPhotoItem: PhotosPickerItem?
  @Binding var inspectorShown: Bool
 
  @State private var textureAspectRatio: CGFloat?
  
  private var currentTextureSize: SIMD2<Int>? {
    guard let texture = coordinator.currentTexture else { return nil }
    return SIMD2(texture.width, texture.height)
  }
  
  private func updateTextureAspectRatio(size: SIMD2<Int>?) {
    guard let size else {
      textureAspectRatio = nil
      return
    }
    
    textureAspectRatio = CGFloat(size.x) / CGFloat(size.y)
  }
  
  var body: some View {
    ZStack {
      Color.black
      
      MetalViewContainer(pipeline: pipeline, coordinator: coordinator)
        .aspectRatio(textureAspectRatio, contentMode: .fit)
      
      if coordinator.cameraPermissionDenied && coordinator.inputSource == .camera {
        cameraPermissionError
      }
    }
    .onAppear {
      updateTextureAspectRatio(size: currentTextureSize)
    }
    .onChange(of: currentTextureSize) { _, newSize in
      updateTextureAspectRatio(size: newSize)
    }
    .inspector(isPresented: $inspectorShown) {
      ParameterControlsView(
        parameters: parameters,
        inputSource: Binding(
          get: { coordinator.inputSource },
          set: { coordinator.inputSource = $0 }
        ),
        selectedPhotoItem: $selectedPhotoItem
      )
      .frame(maxWidth: 700)
      .inspectorColumnWidth(min: 500, ideal: 500, max: 700)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          inspectorShown.toggle()
        } label: {
          Image(systemName: "sidebar.trailing")
        }
      }
    }
  }
  
  private var cameraPermissionError: some View {
    VStack(spacing: 16) {
      Image(systemName: "camera.fill")
        .font(.system(size: 50))
        .foregroundStyle(.red)
      
      Text("Camera Access Required")
        .font(.title2)
        .fontWeight(.semibold)
      
      Text("Please enable camera access in Settings to use camera input")
        .font(.body)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
      
      Button {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
      } label: {
        Text("Open System Settings")
          .fontWeight(.semibold)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(32)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .padding()
  }
}
#endif
