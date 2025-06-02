#include <metal_stdlib>
using namespace metal;

kernel void invertFilter(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;

    float4 color = inTexture.read(gid);
    color.rgb = 1.0 - color.rgb; // Invert colors
    outTexture.write(color, gid);
}
