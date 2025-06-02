#include <metal_stdlib>
using namespace metal;

// Vertex data for a fullscreen quad
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    float4 positions[4] = {
        float4(-1,  1, 0, 1),
        float4(-1, -1, 0, 1),
        float4( 1,  1, 0, 1),
        float4( 1, -1, 0, 1)
    };
    
    float2 texCoords[4] = {
        float2(0, 0),
        float2(0, 1),
        float2(1, 0),
        float2(1, 1)
    };
    
    VertexOut out;
    out.position = positions[vertexID];
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge);
    return tex.sample(s, in.texCoord);
}
