#include <metal_stdlib>
using namespace metal;

// Vertex input struct
struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

// Vertex output struct
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Vertex shader
vertex VertexOut vertex_passthrough(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0, 1);
    out.texCoord = in.texCoord;
    return out;
}

// Fragment shader with grayscale toggle
fragment float4 fragment_filter(VertexOut in [[stage_in]],
                                texture2d<float> inputTexture [[texture(0)]],
                                sampler s [[sampler(0)]],
                                constant bool& filterEnabled [[buffer(0)]]) {

    float4 color = inputTexture.sample(s, in.texCoord);
    if (filterEnabled) {
        float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
        return float4(gray, gray, gray, color.a);
    } else {
        return color;
    }
}
