import Metal
import simd

class HoughTransformShader: Shader {
  var inputTexture: MTLTexture?
  var outputTexture: MTLTexture? // Not used directly, as output is accumulatorBuffer
  
  var accumulatorBuffer: MTLBuffer?
  var accumulatorTexture: MTLTexture? // For visualization
  
  /// Precomputed sin/cos lookup table: float2(cos(theta), sin(theta)) for each theta index
  private var trigTableBuffer: MTLBuffer?
  private var trigTableNumThetas: Int = 0
  
  private let pipelineState: MTLComputePipelineState
  private let clearPipelineState: MTLComputePipelineState
  private let visualizePipelineState: MTLComputePipelineState
  private let device: MTLDevice
  
  var parameters: HoughParameters?
  
  private var accWidth: Int = 0
  private var accHeight: Int = 0
  
  init(device: MTLDevice, library: MTLLibrary) throws {
    self.device = device
    // Use optimized 2D kernel with trig lookup table instead of 3D kernel
    self.pipelineState = try library.computePipeline(for: "houghAccumulatorKernel")
    self.clearPipelineState = try library.computePipeline(for: "clearAccumulatorKernel")
    self.visualizePipelineState = try library.computePipeline(for: "visualizeAccumulatorKernel")
  }
  
  func perform(in commandBuffer: MTLCommandBuffer) throws {
    guard let inputTexture = inputTexture,
          let parameters = parameters else { return }
    
    // 1. Calculate dimensions
    let (accW, accH, maxRho) = calculateAccumulatorDimensions(inputWidth: inputTexture.width, inputHeight: inputTexture.height, parameters: parameters)
    self.accWidth = accW
    self.accHeight = accH
    
    // 2. Ensure accumulator buffer, texture, and trig lookup table
    ensureAccumulatorBuffer(width: accW, height: accH)
    ensureAccumulatorTexture(width: accW, height: accH)
    ensureTrigTableBuffer(numThetas: accW, thetaResolution: parameters.thetaResolutionRadians)
    
    // 3. Clear Accumulator
    clearAccumulator(commandBuffer: commandBuffer, width: accW, height: accH)
    
    // 4. Perform Hough Transform (optimized 2D kernel with trig lookup)
    guard let encoder = commandBuffer.makeComputeCommandEncoder(),
          let trigTable = trigTableBuffer else { return }
    encoder.label = "Hough Transform 2D"
    
    encoder.setComputePipelineState(pipelineState)
    encoder.setTexture(inputTexture, index: 0)
    encoder.setBuffer(accumulatorBuffer, offset: 0, index: 0)
    
    var houghParams = HoughParams(
      rhoResolution: parameters.rhoResolution,
      thetaResolution: parameters.thetaResolutionRadians,
      accumulatorThreshold: Int32(parameters.accumulatorThreshold),
      maxLines: Int32(parameters.maxLines),
      useProbabilistic: 0,
      imageWidth: Int32(inputTexture.width),
      imageHeight: Int32(inputTexture.height),
      accumulatorWidth: Int32(accW),
      accumulatorHeight: Int32(accH),
      maxRho: maxRho
    )
    
    encoder.setBytes(&houghParams, length: MemoryLayout<HoughParams>.stride, index: 1)
    encoder.setBuffer(trigTable, offset: 0, index: 2)
    
    // 2D Dispatch: one thread per image pixel (theta loop is inside kernel)
    let width = inputTexture.width
    let height = inputTexture.height
    
    let w = pipelineState.threadExecutionWidth
    let h = pipelineState.maxTotalThreadsPerThreadgroup / w
    let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
    
    let threadgroups = MTLSize(
      width: (width + w - 1) / w,
      height: (height + h - 1) / h,
      depth: 1
    )
    
    encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
    
    // Visualize accumulator to texture
    visualizeAccumulator(commandBuffer: commandBuffer, width: accW, height: accH, params: houghParams)
  }
  
  private func calculateAccumulatorDimensions(inputWidth: Int, inputHeight: Int, parameters: HoughParameters) -> (Int, Int, Float) {
    let maxRho = sqrt(Float(inputWidth * inputWidth + inputHeight * inputHeight))
    let accumulatorWidth = Int(Float.pi / parameters.thetaResolutionRadians)
    let accumulatorHeight = Int((2 * maxRho) / parameters.rhoResolution)
    return (accumulatorWidth, accumulatorHeight, maxRho)
  }
  
  private func ensureAccumulatorBuffer(width: Int, height: Int) {
    let size = width * height * MemoryLayout<UInt32>.stride
    if accumulatorBuffer == nil || accumulatorBuffer!.length < size {
      accumulatorBuffer = device.makeBuffer(length: size, options: .storageModePrivate)
    }
  }
  
  private func ensureAccumulatorTexture(width: Int, height: Int) {
    if accumulatorTexture?.width != width || accumulatorTexture?.height != height {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba32Float,
        width: width,
        height: height,
        mipmapped: false
      )
      descriptor.usage = [.shaderRead, .shaderWrite]
      descriptor.storageMode = .private
      accumulatorTexture = device.makeTexture(descriptor: descriptor)
    }
  }
  
  /// Ensures the sin/cos lookup table buffer is created and populated for the given number of theta values
  private func ensureTrigTableBuffer(numThetas: Int, thetaResolution: Float) {
    guard numThetas != trigTableNumThetas else { return }
    
    trigTableNumThetas = numThetas
    let bufferSize = numThetas * MemoryLayout<SIMD2<Float>>.stride
    
    // Use shared storage so we can write from CPU
    guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else { return }
    
    // Populate with precomputed cos/sin pairs
    let ptr = buffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: numThetas)
    for thetaIdx in 0..<numThetas {
      let theta = Float(thetaIdx) * thetaResolution
      ptr[thetaIdx] = SIMD2<Float>(cos(theta), sin(theta))
    }
    
    trigTableBuffer = buffer
  }
  
  private func visualizeAccumulator(commandBuffer: MTLCommandBuffer, width: Int, height: Int, params: HoughParams) {
    guard let buffer = accumulatorBuffer,
          let texture = accumulatorTexture,
          let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.label = "Visualize Accumulator"
    
    var houghParams = params
    encoder.setComputePipelineState(visualizePipelineState)
    encoder.setBuffer(buffer, offset: 0, index: 0)
    encoder.setTexture(texture, index: 0)
    encoder.setBytes(&houghParams, length: MemoryLayout<HoughParams>.stride, index: 1)
    
    let w = visualizePipelineState.threadExecutionWidth
    let h = visualizePipelineState.maxTotalThreadsPerThreadgroup / w
    let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
    let threadgroups = MTLSize(
      width: (width + w - 1) / w,
      height: (height + h - 1) / h,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
  
  private func clearAccumulator(commandBuffer: MTLCommandBuffer, width: Int, height: Int) {
    guard let buffer = accumulatorBuffer,
          let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.label = "Clear Accumulator"
    
    var size = Int32(width * height)
    encoder.setComputePipelineState(clearPipelineState)
    encoder.setBuffer(buffer, offset: 0, index: 0)
    encoder.setBytes(&size, length: MemoryLayout<Int32>.stride, index: 1)
    
    let threadgroupSize = MTLSize(width: 256, height: 1, depth: 1)
    let threadgroups = MTLSize(width: (Int(size) + 255) / 256, height: 1, depth: 1)
    encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
    encoder.endEncoding()
  }
}
