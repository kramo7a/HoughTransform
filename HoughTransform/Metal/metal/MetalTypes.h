#ifndef MetalTypes_h
#define MetalTypes_h

#include <simd/simd.h>

struct EdgeDetectionParams {
  float lowThreshold;
  float highThreshold;
  int useCannyEdgeDetection;
};

struct HoughParams {
  float rhoResolution;
  float thetaResolution;
  int accumulatorThreshold;
  int maxLines;
  int useProbabilistic;
  int imageWidth;
  int imageHeight;
  int accumulatorWidth;
  int accumulatorHeight;
  float maxRho;
};

struct LineParams {
  simd_float4 lineColor;
  float lineThickness;
  float overlayOpacity;
};

struct DetectedLine {
  float rho;
  float theta;
  int votes;
  simd_float2 point1;
  simd_float2 point2;
};

struct Vertex {
  simd_float2 position;
  simd_float2 texCoord;
};

struct BlurParams {
  int kernelSize;
  float sigma;
};

struct RenderParams {
  simd_float2 aspectScale;
};

#endif

