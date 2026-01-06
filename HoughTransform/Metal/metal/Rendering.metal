#include <metal_stdlib>
#import "MetalTypes.h"

using namespace metal;

struct VertexOut {
  float4 position [[position]];
  float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              constant Vertex* vertices [[buffer(0)]],
                              constant RenderParams& params [[buffer(1)]]) {
  VertexOut out;
  // Scale position by aspect ratio to maintain proper fit
  float2 scaledPosition = vertices[vertexID].position * params.aspectScale;
  out.position = float4(scaledPosition, 0.0, 1.0);
  out.texCoord = vertices[vertexID].texCoord;
  return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> sourceTexture [[texture(0)]]) {
  constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
  return sourceTexture.sample(textureSampler, in.texCoord);
}

fragment float4 lineOverlayFragment(VertexOut in [[stage_in]],
                                    texture2d<float> sourceTexture [[texture(0)]],
                                    texture2d<float> linesTexture [[texture(1)]],
                                    constant LineParams& params [[buffer(0)]]) {
  constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
  
  float4 source = sourceTexture.sample(textureSampler, in.texCoord);
  float4 lines = linesTexture.sample(textureSampler, in.texCoord);
  
  float4 result = mix(source, params.lineColor, lines.r * params.overlayOpacity);
  return result;
}
