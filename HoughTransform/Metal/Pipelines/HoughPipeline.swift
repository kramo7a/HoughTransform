import Metal
import MetalKit
import simd
import FactoryKit

final class HoughPipeline: Pipeline {
  
  let parameters: HoughParameters
  let commandQueue: MTLCommandQueue
  let device: MTLDevice
  
  // Shaders
  private let downsampleShader: DownsampleShader
  private let grayscaleShader: GrayscaleShader
  private let blurShader: BlurShader
  private let edgeDetectionShader: EdgeDetectionShader
  private let houghShader: HoughTransformShader
  private let lineDrawerShader: LineDrawerShader
  
  private let presenter: TexturePresenter
  
  // Textures managed by Pipeline
  private var downsampledTexture: MTLTexture?
  private var grayscaleTexture: MTLTexture?
  private var blurredTexture: MTLTexture?
  private var edgeTexture: MTLTexture?
  private var outputTexture: MTLTexture? // Final composite
  private var stageOutputTexture: MTLTexture? // For compositing lines on any stage
  
  private let inflightSemaphore = DispatchSemaphore(value: 3)
  
  // State tracking
  private var inputWidth: Int = 0
  private var inputHeight: Int = 0
  private var processWidth: Int = 0
  private var processHeight: Int = 0
  private var currentDownsampleFactor: Int = 0
  
  init() throws {
    self.device = Container.shared.metalDevice()
    self.parameters = Container.shared.houghParameters()
    guard let commandQueue = device.makeCommandQueue() else {
      throw PipelineError.commandQueueCreationFailed
    }
    self.commandQueue = commandQueue
    
    guard let library = device.makeDefaultLibrary() else {
      throw PipelineError.libraryNotFound
    }
    
    // Initialize Shaders
    self.downsampleShader = try DownsampleShader(library: library)
    self.grayscaleShader = try GrayscaleShader(library: library)
    self.blurShader = try BlurShader(library: library)
    self.edgeDetectionShader = try EdgeDetectionShader(device: device, library: library)
    self.houghShader = try HoughTransformShader(device: device, library: library)
    self.lineDrawerShader = try LineDrawerShader(device: device, library: library)
    
    self.presenter = try TexturePresenter(device: device)
  }
  
  func ensureTextures(width: Int, height: Int) {
    let factor = max(1, parameters.downsampleFactor)
    let needsUpdate = width != inputWidth || height != inputHeight || factor != currentDownsampleFactor
    guard needsUpdate else { return }
    
    inputWidth = width
    inputHeight = height
    currentDownsampleFactor = factor
    processWidth = width / factor
    processHeight = height / factor
    
    let downsampledDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba32Float,
      width: processWidth,
      height: processHeight,
      mipmapped: false
    )
    downsampledDescriptor.usage = [.shaderRead, .shaderWrite]
    downsampledDescriptor.storageMode = .private
    
    downsampledTexture = device.makeTexture(descriptor: downsampledDescriptor)
    grayscaleTexture = device.makeTexture(descriptor: downsampledDescriptor)
    blurredTexture = device.makeTexture(descriptor: downsampledDescriptor)
    edgeTexture = device.makeTexture(descriptor: downsampledDescriptor)
    
    let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba32Float,
      width: width,
      height: height,
      mipmapped: false
    )
    outputDescriptor.usage = [.shaderRead, .shaderWrite]
    outputDescriptor.storageMode = .private
    outputTexture = device.makeTexture(descriptor: outputDescriptor)
  }
  
  func process(inputTexture: MTLTexture, drawable: CAMetalDrawable) {
    inflightSemaphore.wait()
    
    ensureTextures(width: inputTexture.width, height: inputTexture.height)
    
    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      inflightSemaphore.signal()
      return
    }
    
    commandBuffer.addCompletedHandler { [weak self] _ in
      self?.inflightSemaphore.signal()
    }
    
    do {
      // 1. Downsample
      downsampleShader.inputTexture = inputTexture
      downsampleShader.outputTexture = downsampledTexture
      downsampleShader.factor = parameters.downsampleFactor
      try downsampleShader.perform(in: commandBuffer)
      
      // 2. Grayscale
      grayscaleShader.inputTexture = downsampledTexture
      grayscaleShader.outputTexture = grayscaleTexture
      try grayscaleShader.perform(in: commandBuffer)
      
      // 3. Blur
      blurShader.inputTexture = grayscaleTexture
      blurShader.outputTexture = blurredTexture
      blurShader.parameters = parameters
      try blurShader.perform(in: commandBuffer)
      
      // 4. Edge Detection
      edgeDetectionShader.inputTexture = blurredTexture
      edgeDetectionShader.outputTexture = edgeTexture
      edgeDetectionShader.parameters = parameters
      try edgeDetectionShader.perform(in: commandBuffer)
      
      // 5. Hough Transform
      houghShader.inputTexture = edgeTexture
      houghShader.parameters = parameters
      try houghShader.perform(in: commandBuffer)
      
      // 6. Get the base texture for the selected stage
      let stageTexture = selectTextureForStage(parameters.displayStage, inputTexture: inputTexture)
      
      // 7. Draw Lines & Composite on top of selected stage (if overlay is enabled)
      let textureToRender: MTLTexture?
      if parameters.showLinesOverlay, let baseTexture = stageTexture {
        // Ensure output texture matches stage texture dimensions
        ensureStageOutputTexture(width: baseTexture.width, height: baseTexture.height)
        
        // Determine if this is a full-resolution stage or downsampled
        let isFullResolution = (parameters.displayStage == .input)
        
        lineDrawerShader.inputTexture = baseTexture
        lineDrawerShader.outputTexture = stageOutputTexture
        lineDrawerShader.accumulatorBuffer = houghShader.accumulatorBuffer
        lineDrawerShader.parameters = parameters
        // Use appropriate dimensions for line coordinate calculations
        lineDrawerShader.originalWidth = isFullResolution ? inputWidth : processWidth
        lineDrawerShader.originalHeight = isFullResolution ? inputHeight : processHeight
        // Always use edge texture dimensions for accumulator lookup
        lineDrawerShader.edgeWidth = processWidth
        lineDrawerShader.edgeHeight = processHeight
        try lineDrawerShader.perform(in: commandBuffer)
        
        textureToRender = stageOutputTexture
      } else {
        textureToRender = stageTexture
      }
      
      if let texture = textureToRender {
        presenter.draw(texture: texture, in: drawable, commandBuffer: commandBuffer)
      }
      
    } catch {
      print("Pipeline error: \(error)")
    }
    
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
  
  private func selectTextureForStage(
    _ stage: DisplayStage,
    inputTexture: MTLTexture
  ) -> MTLTexture? {
    switch stage {
    case .input:
      return inputTexture
    case .downsampled:
      return downsampledTexture
    case .grayscale:
      return grayscaleTexture
    case .blurred:
      return blurredTexture
    case .edges:
      return edgeTexture
    case .houghAccumulator:
      return houghShader.accumulatorTexture
    }
  }
  
  private func ensureStageOutputTexture(width: Int, height: Int) {
    if stageOutputTexture?.width != width || stageOutputTexture?.height != height {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba32Float,
        width: width,
        height: height,
        mipmapped: false
      )
      descriptor.usage = [.shaderRead, .shaderWrite]
      descriptor.storageMode = .private
      stageOutputTexture = device.makeTexture(descriptor: descriptor)
    }
  }
}
