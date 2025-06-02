#include <metal_stdlib>
using namespace metal;

kernel void invertFilter(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Cache width and height for efficiency
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();

    // Bounds check to avoid out-of-bounds access
    if (gid.x >= width || gid.y >= height) return;

    // Read pixel from input texture at current thread position
    float4 color = inTexture.read(gid);

    // Invert RGB channels (leave alpha untouched)
    color.rgb = 1.0 - color.rgb;

    // Write result to output texture
    outTexture.write(color, gid);
}
