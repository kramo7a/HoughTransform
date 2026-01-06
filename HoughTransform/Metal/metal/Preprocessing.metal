#include <metal_stdlib>
#include <metal_atomic>
#import "MetalTypes.h"

using namespace metal;

kernel void downsampleKernel(texture2d<float, access::read> inputTexture [[texture(0)]],
                             texture2d<float, access::write> outputTexture [[texture(1)]],
                             constant int& factor [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
    return;
  }
  
  float4 sum = float4(0.0);
  int count = 0;
  
  int startX = gid.x * factor;
  int startY = gid.y * factor;
  int inputWidth = inputTexture.get_width();
  int inputHeight = inputTexture.get_height();
  
  for (int dy = 0; dy < factor; dy++) {
    for (int dx = 0; dx < factor; dx++) {
      int x = startX + dx;
      int y = startY + dy;
      if (x < inputWidth && y < inputHeight) {
        sum += inputTexture.read(uint2(x, y));
        count++;
      }
    }
  }
  
  if (count > 0) {
    outputTexture.write(sum / float(count), gid);
  }
}

kernel void grayscaleKernel(texture2d<float, access::read> inputTexture [[texture(0)]],
                            texture2d<float, access::write> outputTexture [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
    return;
  }
  
  float4 color = inputTexture.read(gid);
  float gray = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
  outputTexture.write(float4(gray, gray, gray, 1.0), gid);
}

kernel void clearAccumulatorKernel(device atomic_uint* accumulator [[buffer(0)]],
                                   constant int& size [[buffer(1)]],
                                   uint gid [[thread_position_in_grid]]) {
  if (gid >= uint(size)) {
    return;
  }
  atomic_store_explicit(&accumulator[gid], 0, memory_order_relaxed);
}
