import SwiftUI
import PhotosUI
import Metal
import FactoryKit

struct ContentView: View {
  
  @Injected(\.inputTextureSource) private var coordinator: InputTextureSource
  
  @State private var selectedPhotoItem: PhotosPickerItem?
  
#if os(iOS)
  @State private var sheetProgress: CGFloat = 1.0
#else
  @State private var inspectorShown: Bool = true
#endif
  
  var body: some View {
    Group {
#if os(iOS)
      ContentView_iOS(
        selectedPhotoItem: $selectedPhotoItem,
        sheetProgress: $sheetProgress
      )
#else
      ContentView_macOS(
        selectedPhotoItem: $selectedPhotoItem,
        inspectorShown: $inspectorShown
      )
#endif
    }.task {
      await coordinator.start()
    }
    .onChange(of: coordinator.inputSource) { _, newValue in
      coordinator.switchSource(to: newValue)
    }
    .onChange(of: selectedPhotoItem) { _, newItem in
      Task { await coordinator.loadImage(from: newItem) }
    }
  }
}

struct MetalViewContainer: View {
  let pipeline: any Pipeline
  let coordinator: InputTextureSource
  
  var body: some View {
    MetalView(
      pipeline: pipeline,
      currentTexture: Binding(
        get: { coordinator.currentTexture },
        set: { coordinator.currentTexture = $0 }
      )
    )
#if os(iOS)
    .ignoresSafeArea()
#endif
  }
}

#if DEBUG

#Preview {
  let _ = Container.shared.inputTextureSource.register { @MainActor in InputTextureSourceMock() }
  let _ = Container.shared.houghPipeline.register { @MainActor in PassthroughPipeline() }
  ContentView()
}
#endif
