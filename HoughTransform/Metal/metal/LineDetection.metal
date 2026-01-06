#include <metal_stdlib>
#include <metal_atomic>
#import "MetalTypes.h"

using namespace metal;

kernel void peakDetectionKernel(device uint* accumulator [[buffer(0)]],
                                device DetectedLine* detectedLines [[buffer(1)]],
                                device atomic_uint* lineCount [[buffer(2)]],
                                constant HoughParams& params [[buffer(3)]],
                                uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= uint(params.accumulatorWidth) || gid.y >= uint(params.accumulatorHeight)) {
    return;
  }
  
  int idx = gid.y * params.accumulatorWidth + gid.x;
  uint votes = accumulator[idx];
  
  if (votes < uint(params.accumulatorThreshold)) {
    return;
  }
  
  bool isLocalMax = true;
  int windowSize = 5;
  
  for (int dy = -windowSize; dy <= windowSize && isLocalMax; dy++) {
    for (int dx = -windowSize; dx <= windowSize && isLocalMax; dx++) {
      if (dx == 0 && dy == 0) continue;
      
      int nx = int(gid.x) + dx;
      int ny = int(gid.y) + dy;
      
      if (nx >= 0 && nx < params.accumulatorWidth && ny >= 0 && ny < params.accumulatorHeight) {
        int nidx = ny * params.accumulatorWidth + nx;
        if (accumulator[nidx] > votes) {
          isLocalMax = false;
        }
      }
    }
  }
  
  if (!isLocalMax) {
    return;
  }
  
  uint lineIdx = atomic_fetch_add_explicit(lineCount, 1, memory_order_relaxed);
  
  if (lineIdx >= uint(params.maxLines)) {
    return;
  }
  
  float theta = float(gid.x) * params.thetaResolution;
  float rho = float(gid.y) * params.rhoResolution - params.maxRho;
  
  float cosTheta = cos(theta);
  float sinTheta = sin(theta);
  
  float2 point1, point2;
  
  if (abs(sinTheta) > 0.001) {
    point1.x = 0;
    point1.y = rho / sinTheta;
    point2.x = float(params.imageWidth);
    point2.y = (rho - point2.x * cosTheta) / sinTheta;
  } else {
    point1.x = rho / cosTheta;
    point1.y = 0;
    point2.x = point1.x;
    point2.y = float(params.imageHeight);
  }
  
  detectedLines[lineIdx].rho = rho;
  detectedLines[lineIdx].theta = theta;
  detectedLines[lineIdx].votes = int(votes);
  detectedLines[lineIdx].point1 = point1;
  detectedLines[lineIdx].point2 = point2;
}

kernel void drawLinesKernel(texture2d<float, access::write> outputTexture [[texture(0)]],
                            device DetectedLine* detectedLines [[buffer(0)]],
                            constant uint& lineCount [[buffer(1)]],
                            constant LineParams& params [[buffer(2)]],
                            uint2 gid [[thread_position_in_grid]]) {
  int width = outputTexture.get_width();
  int height = outputTexture.get_height();
  
  if (gid.x >= uint(width) || gid.y >= uint(height)) {
    return;
  }
  
  float2 pixel = float2(gid.x, gid.y);
  float minDist = 999999.0;
  
  for (uint i = 0; i < lineCount; i++) {
    float2 p1 = detectedLines[i].point1;
    float2 p2 = detectedLines[i].point2;
    
    float2 lineDir = p2 - p1;
    float lineLen = length(lineDir);
    if (lineLen < 0.001) continue;
    
    lineDir /= lineLen;
    
    float2 toPixel = pixel - p1;
    float projection = dot(toPixel, lineDir);
    
    float2 closestPoint;
    if (projection < 0) {
      closestPoint = p1;
    } else if (projection > lineLen) {
      closestPoint = p2;
    } else {
      closestPoint = p1 + lineDir * projection;
    }
    
    float dist = length(pixel - closestPoint);
    minDist = min(minDist, dist);
  }
  
  float lineValue = 0.0;
  if (minDist < params.lineThickness) {
    lineValue = 1.0 - (minDist / params.lineThickness);
  }
  
  outputTexture.write(float4(lineValue, lineValue, lineValue, lineValue), gid);
}

kernel void compositeKernel(texture2d<float, access::read> sourceTexture [[texture(0)]],
                            texture2d<float, access::read> linesTexture [[texture(1)]],
                            texture2d<float, access::write> outputTexture [[texture(2)]],
                            constant LineParams& params [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= sourceTexture.get_width() || gid.y >= sourceTexture.get_height()) {
    return;
  }
  
  float4 source = sourceTexture.read(gid);
  float4 lines = linesTexture.read(gid);
  
  float4 result = mix(source, params.lineColor, lines.r * params.overlayOpacity);
  outputTexture.write(result, gid);
}
