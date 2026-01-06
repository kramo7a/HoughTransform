#include <metal_stdlib>
#import "MetalTypes.h"

using namespace metal;

constant float PI = 3.14159265359;

kernel void sobelKernel(texture2d<float, access::read> inputTexture [[texture(0)]],
                        texture2d<float, access::write> gradientMagnitude [[texture(1)]],
                        texture2d<float, access::write> gradientDirection [[texture(2)]],
                        constant EdgeDetectionParams& params [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
    return;
  }
  
  int width = inputTexture.get_width();
  int height = inputTexture.get_height();
  
  if (gid.x == 0 || gid.x >= uint(width - 1) || gid.y == 0 || gid.y >= uint(height - 1)) {
    gradientMagnitude.write(float4(0.0), gid);
    gradientDirection.write(float4(0.0), gid);
    return;
  }
  
  float tl = inputTexture.read(uint2(gid.x - 1, gid.y - 1)).r;
  float t  = inputTexture.read(uint2(gid.x,     gid.y - 1)).r;
  float tr = inputTexture.read(uint2(gid.x + 1, gid.y - 1)).r;
  float l  = inputTexture.read(uint2(gid.x - 1, gid.y)).r;
  float r  = inputTexture.read(uint2(gid.x + 1, gid.y)).r;
  float bl = inputTexture.read(uint2(gid.x - 1, gid.y + 1)).r;
  float b  = inputTexture.read(uint2(gid.x,     gid.y + 1)).r;
  float br = inputTexture.read(uint2(gid.x + 1, gid.y + 1)).r;
  
  float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
  float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
  
  float magnitude = sqrt(gx * gx + gy * gy);
  float direction = atan2(gy, gx);
  
  float normalizedMag = magnitude > params.lowThreshold ? magnitude : 0.0;
  
  gradientMagnitude.write(float4(normalizedMag, normalizedMag, normalizedMag, 1.0), gid);
  gradientDirection.write(float4(direction, 0.0, 0.0, 1.0), gid);
}

kernel void cannyNonMaxSuppressionKernel(texture2d<float, access::read> gradientMagnitude [[texture(0)]],
                                         texture2d<float, access::read> gradientDirection [[texture(1)]],
                                         texture2d<float, access::write> outputTexture [[texture(2)]],
                                         constant EdgeDetectionParams& params [[buffer(0)]],
                                         uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= gradientMagnitude.get_width() || gid.y >= gradientMagnitude.get_height()) {
    return;
  }
  
  int width = gradientMagnitude.get_width();
  int height = gradientMagnitude.get_height();
  
  if (gid.x == 0 || gid.x >= uint(width - 1) || gid.y == 0 || gid.y >= uint(height - 1)) {
    outputTexture.write(float4(0.0), gid);
    return;
  }
  
  float magnitude = gradientMagnitude.read(gid).r;
  float direction = gradientDirection.read(gid).r;
  
  float angle = direction * 180.0 / PI;
  if (angle < 0) angle += 180.0;
  
  float neighbor1 = 0.0;
  float neighbor2 = 0.0;
  
  if ((angle >= 0 && angle < 22.5) || (angle >= 157.5 && angle <= 180)) {
    neighbor1 = gradientMagnitude.read(uint2(gid.x + 1, gid.y)).r;
    neighbor2 = gradientMagnitude.read(uint2(gid.x - 1, gid.y)).r;
  } else if (angle >= 22.5 && angle < 67.5) {
    neighbor1 = gradientMagnitude.read(uint2(gid.x + 1, gid.y - 1)).r;
    neighbor2 = gradientMagnitude.read(uint2(gid.x - 1, gid.y + 1)).r;
  } else if (angle >= 67.5 && angle < 112.5) {
    neighbor1 = gradientMagnitude.read(uint2(gid.x, gid.y - 1)).r;
    neighbor2 = gradientMagnitude.read(uint2(gid.x, gid.y + 1)).r;
  } else if (angle >= 112.5 && angle < 157.5) {
    neighbor1 = gradientMagnitude.read(uint2(gid.x - 1, gid.y - 1)).r;
    neighbor2 = gradientMagnitude.read(uint2(gid.x + 1, gid.y + 1)).r;
  }
  
  float result = 0.0;
  if (magnitude >= neighbor1 && magnitude >= neighbor2) {
    if (magnitude >= params.highThreshold) {
      result = 1.0;
    } else if (magnitude >= params.lowThreshold) {
      result = 0.5;
    }
  }
  
  outputTexture.write(float4(result, result, result, 1.0), gid);
}

kernel void cannyHysteresisKernel(texture2d<float, access::read> inputTexture [[texture(0)]],
                                  texture2d<float, access::write> outputTexture [[texture(1)]],
                                  uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
    return;
  }
  
  float center = inputTexture.read(gid).r;
  
  if (center >= 1.0) {
    outputTexture.write(float4(1.0, 1.0, 1.0, 1.0), gid);
    return;
  }
  
  if (center < 0.5) {
    outputTexture.write(float4(0.0, 0.0, 0.0, 1.0), gid);
    return;
  }
  
  int width = inputTexture.get_width();
  int height = inputTexture.get_height();
  
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      int x = clamp(int(gid.x) + i, 0, width - 1);
      int y = clamp(int(gid.y) + j, 0, height - 1);
      if (inputTexture.read(uint2(x, y)).r >= 1.0) {
        outputTexture.write(float4(1.0, 1.0, 1.0, 1.0), gid);
        return;
      }
    }
  }
  
  outputTexture.write(float4(0.0, 0.0, 0.0, 1.0), gid);
}
