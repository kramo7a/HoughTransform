//
//  DownsampleShader.swift
//  HoughTransform
//
//  Created by Alex Dolenko on 08.01.2026.
//


import Metal

class DownsampleShader: Shader {
  var inputTexture: MTLTexture?
  var outputTexture: MTLTexture?
  var factor: Int = 1
  
  private let pipelineState: MTLComputePipelineState
  
  init(library: MTLLibrary) throws {
    self.pipelineState = try library.computePipeline(for: "downsampleKernel")
  }
  
  func perform(in commandBuffer: MTLCommandBuffer) throws {
    guard let input = inputTexture, let output = outputTexture,
          let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.label = "Downsample"
    
    var f = Int32(max(1, factor))
    
    encoder.setComputePipelineState(pipelineState)
    encoder.setTexture(input, index: 0)
    encoder.setTexture(output, index: 1)
    encoder.setBytes(&f, length: MemoryLayout<Int32>.stride, index: 0)
    
    let w = pipelineState.threadExecutionWidth
    let h = pipelineState.maxTotalThreadsPerThreadgroup / w
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