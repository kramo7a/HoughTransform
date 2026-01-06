import SwiftUI
import MetalKit
import FactoryKit
import Combine

#if os(iOS) || os(visionOS)
struct MetalView: UIViewRepresentable {
  
  @Injected(\.metalDevice) private var device
  @Injected(\.houghParameters) private var houghParameters
  
  let pipeline: any Pipeline
  @Binding var currentTexture: MTLTexture?
  
  func makeCoordinator() -> Coordinator {
    Coordinator(pipeline: pipeline, parameters: houghParameters)
  }
  
  func makeUIView(context: Context) -> MTKView {
    let view = MTKView()
    view.device = device
    view.delegate = context.coordinator
    view.preferredFramesPerSecond = houghParameters.fps
    view.colorPixelFormat = .bgra8Unorm
    view.framebufferOnly = false
    view.enableSetNeedsDisplay = true
    view.isPaused = true
    view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    
    context.coordinator.mtkView = view
    
    return view
  }
  
  func updateUIView(_ uiView: MTKView, context: Context) {
    context.coordinator.currentTexture = currentTexture
    uiView.setNeedsDisplay()
  }
}
#endif

#if os(macOS)
struct MetalView: NSViewRepresentable {
  @Injected(\.metalDevice) private var device: MTLDevice
  @Injected(\.houghParameters) private var houghParameters
  
  let pipeline: any Pipeline
  @Binding var currentTexture: MTLTexture?
  
  func makeCoordinator() -> Coordinator {
    Coordinator(pipeline: pipeline, parameters: houghParameters)
  }
  
  func makeNSView(context: Context) -> MTKView {
    let view = MTKView()
    view.device = device
    view.delegate = context.coordinator
    view.preferredFramesPerSecond = houghParameters.fps
    view.colorPixelFormat = .bgra8Unorm
    view.framebufferOnly = false
    view.enableSetNeedsDisplay = true
    view.isPaused = true
    view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    
    context.coordinator.mtkView = view
    
    return view
  }
  
  func updateNSView(_ nsView: MTKView, context: Context) {
    context.coordinator.currentTexture = currentTexture
    nsView.setNeedsDisplay(nsView.bounds)
  }
}
#endif

final class Coordinator: NSObject, MTKViewDelegate {
  let pipeline: any Pipeline
  var currentTexture: MTLTexture?
  weak var mtkView: MTKView? {
    didSet { subscribeToParameters() }
  }
  
  private let parameters: HoughParameters
  private var cancellable: AnyCancellable?
  
  init(pipeline: any Pipeline, parameters: HoughParameters) {
    self.pipeline = pipeline
    self.parameters = parameters
  }
  
  private func subscribeToParameters() {
    cancellable = parameters.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let mtkView = self?.mtkView else { return }
#if os(macOS)
        mtkView.setNeedsDisplay(mtkView.bounds)
#else
        mtkView.setNeedsDisplay()
#endif
      }
  }
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
  
  func draw(in view: MTKView) {
    guard let texture = currentTexture,
          let drawable = view.currentDrawable else { return }
    
    pipeline.process(inputTexture: texture, drawable: drawable)
  }
}

