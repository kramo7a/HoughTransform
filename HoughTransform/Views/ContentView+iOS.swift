#if os(iOS)
import SwiftUI
import PhotosUI
import FactoryKit

struct ContentView_iOS: View {
  
  @Injected(\.houghParameters) private var parameters: HoughParameters
  @Injected(\.houghPipeline) private var pipeline: any Pipeline
  @Injected(\.inputTextureSource) private var coordinator: InputTextureSource
  
  @Binding var selectedPhotoItem: PhotosPickerItem?
  @Binding var sheetProgress: CGFloat
  
  private let sheetShare: CGFloat = 0.618
  
  @State private var contentDragStartProgress: CGFloat?
  
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        MetalViewContainer(pipeline: pipeline, coordinator: coordinator)
          .sheetTransform(progress: sheetProgress, height: geometry.size.height, sheetShare: sheetShare)
          .contentShape(Rectangle())
          .gesture(contentDragGesture(maxHeight: geometry.size.height * sheetShare))
        
        DraggableSheet(progress: $sheetProgress, maxHeight: geometry.size.height * sheetShare) {
          ParameterControlsView(
            parameters: parameters,
            inputSource: Binding(
              get: { coordinator.inputSource },
              set: { coordinator.inputSource = $0 }
            ),
            selectedPhotoItem: $selectedPhotoItem
          )
        }
        
        bottomButton(geometry: geometry)
        
        if coordinator.cameraPermissionDenied && coordinator.inputSource == .camera {
          cameraPermissionError
        }
      }
      .ignoresSafeArea()
    }
  }
  
  private func contentDragGesture(maxHeight: CGFloat) -> some Gesture {
    DragGesture()
      .onChanged { value in
        let startProgress = contentDragStartProgress ?? sheetProgress
        if contentDragStartProgress == nil {
          contentDragStartProgress = sheetProgress
        }
        let dragProgress = -value.translation.height / maxHeight
        sheetProgress = min(1, max(0, startProgress + dragProgress))
      }
      .onEnded { value in
        let velocity = value.predictedEndLocation.y - value.location.y
        let threshold = maxHeight * 0.3
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
          if value.translation.height > threshold || velocity > 100 {
            sheetProgress = 0
          } else if value.translation.height < -threshold || velocity < -100 {
            sheetProgress = 1
          } else {
            sheetProgress = sheetProgress > 0.5 ? 1 : 0
          }
        }
        contentDragStartProgress = nil
      }
  }
  
  @ViewBuilder
  private func bottomButton(geometry: GeometryProxy) -> some View {
    let buttonHeight: CGFloat = 32
    let sheetHeight = geometry.size.height * sheetShare
    let sheetOffset = sheetHeight * (1 - sheetProgress)
    
    VStack {
      Spacer()
      
      HStack {
        Spacer()
        Button {
          withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            sheetProgress = sheetProgress > 0.5 ? 0 : 1
          }
        } label: {
          Image(systemName: "slider.horizontal.3")
            .font(.title2)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .frame(width: 32, height: buttonHeight)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.glass)
        .padding()
      }
      .offset(y: sheetOffset - sheetHeight - buttonHeight / 2 - 16 + geometry.safeAreaInsets.bottom)
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
      
      if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
        Button {
          UIApplication.shared.open(settingsURL)
        } label: {
          Text("Open Settings")
            .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(32)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .padding()
  }
}
#endif
