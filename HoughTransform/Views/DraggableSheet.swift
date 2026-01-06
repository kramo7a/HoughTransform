#if os(iOS)
import SwiftUI

struct DraggableSheet<Content: View>: View {
  @Binding var progress: CGFloat
  let maxHeight: CGFloat
  @ViewBuilder let content: () -> Content
  
  @State private var dragStartProgress: CGFloat?
  @State private var scrollViewDragging = false
  
  private var sheetOffset: CGFloat {
    maxHeight * (1 - progress)
  }
  
  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        Spacer()
        
        VStack(spacing: 0) {
          handle
          
          content()
            .environment(\.sheetScrollHandler, SheetScrollHandler(
              onOverscroll: { translation in
                handleOverscroll(translation: translation)
              },
              onOverscrollEnded: { translation, velocity in
                handleOverscrollEnded(translation: translation, velocity: velocity)
              }
            ))
        }
        .frame(height: maxHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .offset(y: sheetOffset)
        .gesture(dragGesture)
      }
      .ignoresSafeArea(edges: .bottom)
    }
  }
  
  private var handle: some View {
    RoundedRectangle(cornerRadius: 2)
      .fill(.secondary.opacity(0.5))
      .frame(width: 36, height: 4)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity)
  }
  
  private func handleOverscroll(translation: CGFloat) {
    if !scrollViewDragging {
      scrollViewDragging = true
      dragStartProgress = progress
    }
    let startProgress = dragStartProgress ?? progress
    let dragProgress = -translation / maxHeight
    progress = min(1, max(0, startProgress + dragProgress))
  }
  
  private func handleOverscrollEnded(translation: CGFloat, velocity: CGFloat) {
    scrollViewDragging = false
    let threshold = maxHeight * 0.1
    
    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
      if translation > threshold || velocity > 100 {
        progress = 0
      } else if translation < -threshold || velocity < -100 {
        progress = 1
      } else {
        progress = progress > 0.5 ? 1 : 0
      }
    }
    dragStartProgress = nil
  }
  
  private var dragGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        let startProgress = dragStartProgress ?? progress
        if dragStartProgress == nil {
          dragStartProgress = progress
        }
        let dragProgress = -value.translation.height / maxHeight
        progress = min(1, max(0, startProgress + dragProgress))
      }
      .onEnded { value in
        let velocity = value.predictedEndLocation.y - value.location.y
        let threshold = maxHeight * 0.1
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
          if value.translation.height > threshold || velocity > 100 {
            progress = 0
          } else if value.translation.height < -threshold || velocity < -100 {
            progress = 1
          } else {
            progress = progress > 0.5 ? 1 : 0
          }
        }
        dragStartProgress = nil
      }
  }
}

extension View {
  func sheetTransform(progress: CGFloat, height: CGFloat, sheetShare: CGFloat) -> some View {
    let maxOffset = height * (sheetShare / 2)
    let scale = 1.0 - (sheetShare * progress)
    let cornerRadius = 24 * progress
    let offset = -maxOffset * progress
    
    return self
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .scaleEffect(scale)
      .offset(y: offset)
  }
}
#endif
