import Metal
import simd

class LineDrawerShader: Shader {
  var inputTexture: MTLTexture? // Source image (for composite)
  var outputTexture: MTLTexture? // Final output image (composite result)
  
  var accumulatorBuffer: MTLBuffer?
  var detectedLinesBuffer: MTLBuffer?
  var lineCountBuffer: MTLBuffer?
  var linesTexture: MTLTexture? // Intermediate texture with just lines
  
  private let peakDetectionPipeline: MTLComputePipelineState
  private let drawLinesPipeline: MTLComputePipelineState
  private let compositePipeline: MTLComputePipelineState
  private let device: MTLDevice
  
  var parameters: HoughParameters?
  var originalWidth: Int = 0   // Output dimensions (for line drawing)
  var originalHeight: Int = 0
  var edgeWidth: Int = 0       // Edge texture dimensions (for accumulator lookup)
  var edgeHeight: Int = 0
  
  init(device: MTLDevice, library: MTLLibrary) throws {
    self.device = device
    self.peakDetectionPipeline = try library.computePipeline(for: "peakDetectionKernel")
    self.drawLinesPipeline = try library.computePipeline(for: "drawLinesKernel")
    self.compositePipeline = try library.computePipeline(for: "compositeKernel")
  }
  
  func perform(in commandBuffer: MTLCommandBuffer) throws {
    guard let input = inputTexture, let output = outputTexture,
          let accumulator = accumulatorBuffer,
          let parameters = parameters else { return }
    
    ensureBuffers(parameters: parameters)
    ensureLinesTexture(width: input.width, height: input.height)
    
    guard let detectedLines = detectedLinesBuffer,
          let lineCount = lineCountBuffer,
          let linesTex = linesTexture else { return }
    
    // Reset line count
    if let blit = commandBuffer.makeBlitCommandEncoder() {
      blit.fill(buffer: lineCount, range: 0..<MemoryLayout<UInt32>.stride, value: 0)
      blit.endEncoding()
    }
    
    // 1. Peak Detection
    if let encoder = commandBuffer.makeComputeCommandEncoder() {
      encoder.label = "Peak Detection"
      
      let factor = max(1, parameters.downsampleFactor)
      
      // Use edge texture dimensions (set by HoughPipeline) for accumulator lookup
      let (accWidth, accHeight, maxRho) = calculateAccumulatorDimensions(inputWidth: edgeWidth, inputHeight: edgeHeight, parameters: parameters)
      
      // Scale threshold down by factor since votes are proportional to line length in pixels
      // When image is downsampled, lines have fewer edge pixels voting for them
      let scaledThreshold = max(1, parameters.accumulatorThreshold / factor)
      
      // Calculate coordinate scale: ratio of output dimensions to edge dimensions
      // For full-res output: coordScale = factor (e.g., 1920/960 = 2)
      // For downsampled output (e.g., edges stage): coordScale = 1 (960/960 = 1)
      let coordScale = edgeWidth > 0 ? Float(originalWidth) / Float(edgeWidth) : 1.0
      
      var houghParams = HoughParams(
        rhoResolution: parameters.rhoResolution * coordScale,
        thetaResolution: parameters.thetaResolutionRadians,
        accumulatorThreshold: Int32(scaledThreshold),
        maxLines: Int32(parameters.maxLines),
        useProbabilistic: 0,
        imageWidth: Int32(originalWidth),
        imageHeight: Int32(originalHeight),
        accumulatorWidth: Int32(accWidth),
        accumulatorHeight: Int32(accHeight),
        maxRho: maxRho * coordScale
      )
      
      encoder.setComputePipelineState(peakDetectionPipeline)
      encoder.setBuffer(accumulator, offset: 0, index: 0)
      encoder.setBuffer(detectedLines, offset: 0, index: 1)
      encoder.setBuffer(lineCount, offset: 0, index: 2)
      encoder.setBytes(&houghParams, length: MemoryLayout<HoughParams>.stride, index: 3)
      
      let w = peakDetectionPipeline.threadExecutionWidth
      let h = peakDetectionPipeline.maxTotalThreadsPerThreadgroup / w
      let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
      let threadgroups = MTLSize(
        width: (accWidth + w - 1) / w,
        height: (accHeight + h - 1) / h,
        depth: 1
      )
      encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
      encoder.endEncoding()
    }
    
    // 2. Draw Lines
    if let encoder = commandBuffer.makeComputeCommandEncoder() {
      encoder.label = "Draw Lines"
      
      // To avoid CPU readback stall, we rely on the buffer content.
      // Note: The original implementation likely had a race or stall.
      // Here we assume drawLinesKernel is updated or we accept the existing behavior (using a pointer/reference in kernel).
      // We modified the kernel to take `device atomic_uint*` (pointer), so we can pass the buffer directly.
      
      var lineParams = LineParams(
        lineColor: parameters.lineColorSIMD,
        lineThickness: parameters.lineThickness,
        overlayOpacity: parameters.overlayOpacity
      )
      
      encoder.setComputePipelineState(drawLinesPipeline)
      encoder.setTexture(linesTex, index: 0)
      encoder.setBuffer(detectedLines, offset: 0, index: 0)
      encoder.setBuffer(lineCount, offset: 0, index: 1) // Pass buffer directly
      encoder.setBytes(&lineParams, length: MemoryLayout<LineParams>.stride, index: 2)
      
      let w = drawLinesPipeline.threadExecutionWidth
      let h = drawLinesPipeline.maxTotalThreadsPerThreadgroup / w
      let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
      let threadgroups = MTLSize(
        width: (linesTex.width + w - 1) / w,
        height: (linesTex.height + h - 1) / h,
        depth: 1
      )
      encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
      encoder.endEncoding()
    }
    
    // 3. Composite
    if let encoder = commandBuffer.makeComputeCommandEncoder() {
      encoder.label = "Composite"
      
      var lineParams = LineParams(
        lineColor: parameters.lineColorSIMD,
        lineThickness: parameters.lineThickness,
        overlayOpacity: parameters.overlayOpacity
      )
      
      encoder.setComputePipelineState(compositePipeline)
      encoder.setTexture(input, index: 0)
      encoder.setTexture(linesTex, index: 1)
      encoder.setTexture(output, index: 2)
      encoder.setBytes(&lineParams, length: MemoryLayout<LineParams>.stride, index: 0)
      
      let w = compositePipeline.threadExecutionWidth
      let h = compositePipeline.maxTotalThreadsPerThreadgroup / w
      let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
      let threadgroups = MTLSize(
        width: (output.width + w - 1) / w,
        height: (output.height + h - 1) / h,
        depth: 1
      )
      encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
      encoder.endEncoding()
    }
  }
  
  private func ensureBuffers(parameters: HoughParameters) {
    let maxLines = Int(parameters.maxLines)
    if detectedLinesBuffer == nil || detectedLinesBuffer!.length < maxLines * MemoryLayout<DetectedLine>.stride {
      detectedLinesBuffer = device.makeBuffer(length: MemoryLayout<DetectedLine>.stride * maxLines, options: .storageModeShared)
    }
    if lineCountBuffer == nil {
      lineCountBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
    }
  }
  
  private func ensureLinesTexture(width: Int, height: Int) {
    if linesTexture?.width != width || linesTexture?.height != height {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
      descriptor.usage = [.shaderRead, .shaderWrite]
      descriptor.storageMode = .private
      linesTexture = device.makeTexture(descriptor: descriptor)
    }
  }
  
  private func calculateAccumulatorDimensions(inputWidth: Int, inputHeight: Int, parameters: HoughParameters) -> (Int, Int, Float) {
    let maxRho = sqrt(Float(inputWidth * inputWidth + inputHeight * inputHeight))
    let accumulatorWidth = Int(Float.pi / parameters.thetaResolutionRadians)
    let accumulatorHeight = Int((2 * maxRho) / parameters.rhoResolution)
    return (accumulatorWidth, accumulatorHeight, maxRho)
  }
}
