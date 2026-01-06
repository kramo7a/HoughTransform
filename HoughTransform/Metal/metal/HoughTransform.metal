#include <metal_stdlib>
#include <metal_atomic>
#import "MetalTypes.h"

using namespace metal;

// Optimized 3D Hough Transform
kernel void houghTransform_3d(texture2d<float, access::read> edgeTexture [[texture(0)]],
                              device atomic_uint* accumulator [[buffer(0)]],
                              constant HoughParams& params [[buffer(1)]],
                              uint3 gid [[thread_position_in_grid]]) {
  if (gid.x >= uint(params.imageWidth) || gid.y >= uint(params.imageHeight)) {
    return;
  }
  
  float edge = edgeTexture.read(gid.xy).r;
  if (edge < 0.5) {
    return;
  }
  
  // Use gid.z for theta loop
  int thetaIdx = gid.z;
  if (thetaIdx >= params.accumulatorWidth) {
      return;
  }

  float theta = float(thetaIdx) * params.thetaResolution;
  float rho = float(gid.x) * cos(theta) + float(gid.y) * sin(theta);
  
  int rhoIdx = int((rho + params.maxRho) / params.rhoResolution);
  
  if (rhoIdx >= 0 && rhoIdx < params.accumulatorHeight) {
    int accIdx = rhoIdx * params.accumulatorWidth + thetaIdx;
    atomic_fetch_add_explicit(&accumulator[accIdx], 1, memory_order_relaxed);
  }
}

kernel void houghAccumulatorKernel(texture2d<float, access::read> edgeTexture [[texture(0)]],
                                   device atomic_uint* accumulator [[buffer(0)]],
                                   constant HoughParams& params [[buffer(1)]],
                                   device float2* trigTable [[buffer(2)]],
                                   uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= uint(params.imageWidth) || gid.y >= uint(params.imageHeight)) {
    return;
  }
  
  float edge = edgeTexture.read(gid).r;
  if (edge < 0.5) {
    return;
  }
  
  float x = float(gid.x);
  float y = float(gid.y);
  
  int numThetas = params.accumulatorWidth;
  
  for (int thetaIdx = 0; thetaIdx < numThetas; thetaIdx++) {
    // Use precomputed cos/sin from lookup table: trigTable[i] = float2(cos(theta), sin(theta))
    float2 trig = trigTable[thetaIdx];
    float rho = x * trig.x + y * trig.y;
    
    int rhoIdx = int((rho + params.maxRho) / params.rhoResolution);
    
    if (rhoIdx >= 0 && rhoIdx < params.accumulatorHeight) {
      int accIdx = rhoIdx * params.accumulatorWidth + thetaIdx;
      atomic_fetch_add_explicit(&accumulator[accIdx], 1, memory_order_relaxed);
    }
  }
}

kernel void probabilisticHoughKernel(texture2d<float, access::read> edgeTexture [[texture(0)]],
                                     device atomic_uint* accumulator [[buffer(0)]],
                                     constant HoughParams& params [[buffer(1)]],
                                     device uint* randomSeed [[buffer(2)]],
                                     uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= uint(params.imageWidth) || gid.y >= uint(params.imageHeight)) {
    return;
  }
  
  float edge = edgeTexture.read(gid).r;
  if (edge < 0.5) {
    return;
  }
  
  uint seed = randomSeed[gid.y * params.imageWidth + gid.x];
  seed = seed * 1103515245 + 12345;
  float random = float(seed & 0x7FFFFFFF) / float(0x7FFFFFFF);
  
  if (random > 0.3) {
    return;
  }
  
  float x = float(gid.x);
  float y = float(gid.y);
  
  int numThetas = params.accumulatorWidth;
  
  for (int thetaIdx = 0; thetaIdx < numThetas; thetaIdx++) {
    float theta = float(thetaIdx) * params.thetaResolution;
    float rho = x * cos(theta) + y * sin(theta);
    
    int rhoIdx = int((rho + params.maxRho) / params.rhoResolution);
    
    if (rhoIdx >= 0 && rhoIdx < params.accumulatorHeight) {
      int accIdx = rhoIdx * params.accumulatorWidth + thetaIdx;
      atomic_fetch_add_explicit(&accumulator[accIdx], 1, memory_order_relaxed);
    }
  }
}

kernel void visualizeAccumulatorKernel(device uint* accumulator [[buffer(0)]],
                                       texture2d<float, access::write> outputTexture [[texture(0)]],
                                       constant HoughParams& params [[buffer(1)]],
                                       uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= uint(params.accumulatorWidth) || gid.y >= uint(params.accumulatorHeight)) {
    return;
  }
  
  int idx = gid.y * params.accumulatorWidth + gid.x;
  uint votes = accumulator[idx];
  
  // Normalize to 0-1 range using threshold as reference
  float normalized = min(float(votes) / float(params.accumulatorThreshold * 2), 1.0);
  
  // Heat map coloring: blue -> cyan -> green -> yellow -> red
  float4 color;
  if (normalized < 0.25) {
    float t = normalized / 0.25;
    color = float4(0.0, t, 1.0, 1.0); // blue to cyan
  } else if (normalized < 0.5) {
    float t = (normalized - 0.25) / 0.25;
    color = float4(0.0, 1.0, 1.0 - t, 1.0); // cyan to green
  } else if (normalized < 0.75) {
    float t = (normalized - 0.5) / 0.25;
    color = float4(t, 1.0, 0.0, 1.0); // green to yellow
  } else {
    float t = (normalized - 0.75) / 0.25;
    color = float4(1.0, 1.0 - t, 0.0, 1.0); // yellow to red
  }
  
  outputTexture.write(color, gid);
}
