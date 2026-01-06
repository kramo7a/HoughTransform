#include <metal_stdlib>
#import "MetalTypes.h"

using namespace metal;

// Compute Gaussian weight for a given offset and sigma
inline float gaussianWeight(int x, int y, float sigma) {
  float sigma2 = sigma * sigma;
  return exp(-(float(x * x + y * y)) / (2.0 * sigma2)) / (2.0 * M_PI_F * sigma2);
}

kernel void gaussianBlurKernel(texture2d<float, access::read> inputTexture [[texture(0)]],
                               texture2d<float, access::write> outputTexture [[texture(1)]],
                               constant BlurParams& params [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
    return;
  }
  
  int width = inputTexture.get_width();
  int height = inputTexture.get_height();
  
  int halfSize = params.kernelSize / 2;
  float sigma = params.sigma;
  
  float sum = 0.0;
  float weightSum = 0.0;
  
  for (int j = -halfSize; j <= halfSize; j++) {
    for (int i = -halfSize; i <= halfSize; i++) {
      int x = clamp(int(gid.x) + i, 0, width - 1);
      int y = clamp(int(gid.y) + j, 0, height - 1);
      float pixel = inputTexture.read(uint2(x, y)).r;
      float weight = gaussianWeight(i, j, sigma);
      sum += pixel * weight;
      weightSum += weight;
    }
  }
  
  // Normalize by total weight to ensure brightness preservation
  float result = sum / weightSum;
  outputTexture.write(float4(result, result, result, 1.0), gid);
}
