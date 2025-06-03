#include <metal_stdlib>
using namespace metal;

#define K_EPSILON 1e-5
#define PI 3.14159265359

struct Uniforms {
    float2 resolution;
    float time;
    int warpMode;       // 0: none, 1: sine wave, 2: magnify
    int filterMode;     // 0=none, 1=grayscale ... 9=vignette
    float brightness;
    float contrast;
    float2 magnifyCenter;
    float magnifyRadius;
    float magnifyStrength;
};

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

inline float2 safeNormalize(float2 v) {
    float len = length(v);
    return (len > K_EPSILON) ? (v / len) : float2(0.0);
}

float4 sineWaveWarp(float4 pos, float2 uv, float time) {
    float amp = 0.05, freq = 10.0;
    // Scale amp from UV to clip space (~2.0 range)
    float2 offset = float2(0.0, sin(uv.x * freq + time * 5.0) * amp * 2.0);
    pos.xy += offset;
    return pos;
}

float4 magnifyingGlassWarp(float4 pos, float2 uv, float2 center, float radius, float strength) {
    float dist = distance(uv, center);
    if (dist < radius) {
        float factor = smoothstep(radius, 0.0, dist); // stronger at center
        float2 dir = safeNormalize(center - uv);
        float2 offset = dir * factor * strength * 2.0; // *2.0 to convert UV delta to clip space delta
        pos.xy += offset;
    }
    return pos;
}

vertex VertexOut vertex_main(VertexIn in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
    VertexOut out;
    float4 pos = in.position;
    float2 uv = in.uv;

    if (u.warpMode == 1) pos = sineWaveWarp(pos, uv, u.time);
    else if (u.warpMode == 2) pos = magnifyingGlassWarp(pos, uv, u.magnifyCenter, u.magnifyRadius, u.magnifyStrength);

    out.position = pos;
    out.uv = uv;
    return out;
}

float4 filterGrayscale(float4 c) {
    float gray = dot(c.rgb, float3(0.299, 0.587, 0.114));
    return float4(gray, gray, gray, c.a);
}

float4 filterInvert(float4 c) {
    return float4(1.0 - c.rgb, c.a);
}

float4 filterSepia(float4 c) {
    float3 sepia = float3(
        dot(c.rgb, float3(0.393, 0.769, 0.189)),
        dot(c.rgb, float3(0.349, 0.686, 0.168)),
        dot(c.rgb, float3(0.272, 0.534, 0.131))
    );
    return float4(min(sepia, float3(1.0)), c.a);
}

float4 filterBrightness(float4 c, float amt) {
    c.rgb = clamp(c.rgb + amt, 0.0, 1.0);
    return c;
}

float4 filterContrast(float4 c, float contrast) {
    c.rgb = clamp((c.rgb - 0.5) * contrast + 0.5, 0.0, 1.0);
    return c;
}

float4 applyToneMapping(float4 c) {
    c.rgb = c.rgb / (c.rgb + float3(1.0));
    return c;
}

float4 applyChromaticAberration(texture2d<float> tex, float2 uv, sampler s) {
    float amt = 0.005;
    float r = tex.sample(s, uv + float2(amt, 0)).r;
    float g = tex.sample(s, uv).g;
    float b = tex.sample(s, uv - float2(amt, 0)).b;
    float a = tex.sample(s, uv).a;
    return float4(r, g, b, a);
}

inline float rand(float2 co) {
    return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
}

float4 applyFilmGrain(float4 c, float2 uv, float time) {
    float grain = (rand(uv * 1000.0 + time * 10.0) - 0.5) * 0.05;
    c.rgb = clamp(c.rgb + grain, 0.0, 1.0);
    return c;
}

float4 applyVignette(float4 c, float2 uv) {
    float2 centered = uv - 0.5;
    float v = smoothstep(0.5, 0.8, length(centered));
    v = 1.0 - v; // invert to darken edges
    c.rgb *= v;
    return c;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              sampler s [[sampler(0)]],
                              constant Uniforms &u [[buffer(1)]])
{
    float2 uv = in.uv;
    float4 c = tex.sample(s, uv);

    switch (u.filterMode) {
        case 1: c = filterGrayscale(c); break;
        case 2: c = filterInvert(c); break;
        case 3: c = filterSepia(c); break;
        case 4: c = filterBrightness(c, u.brightness); break;
        case 5: c = filterContrast(c, u.contrast); break;
        case 6: c = applyToneMapping(c); break;
        case 7: c = applyChromaticAberration(tex, uv, s); break;
        case 8: c = applyFilmGrain(c, uv, u.time); break;
        case 9: c = applyVignette(c, uv); break;
        default: break;
    }

    return float4(clamp(c.rgb, 0.0, 1.0), c.a);
}

inline float gaussianWeight(int i, float sigma) {
    return exp(-float(i * i) / (2.0 * sigma * sigma));
}

kernel void gaussianBlurHorizontal(texture2d<float, access::read>  inTex  [[texture(0)]],
                                   texture2d<float, access::write> outTex [[texture(1)]],
                                   uint2 gid [[thread_position_in_grid]])
{
    uint width = outTex.get_width(), height = outTex.get_height();
    if (gid.x >= width || gid.y >= height) return;

    constexpr int radius = 5;
    constexpr float sigma = 3.0;
    float4 color = float4(0.0);
    float weightSum = 0.0;

    for (int i = -radius; i <= radius; ++i) {
        int x = clamp(int(gid.x) + i, 0, int(width) - 1);
        float w = gaussianWeight(i, sigma);
        color += inTex.read(uint2(x, gid.y)) * w;
        weightSum += w;
    }
    outTex.write(color / weightSum, gid);
}

kernel void gaussianBlurVertical(texture2d<float, access::read>  inTex  [[texture(0)]],
                                 texture2d<float, access::write> outTex [[texture(1)]],
                                 uint2 gid [[thread_position_in_grid]])
{
    uint width = outTex.get_width(), height = outTex.get_height();
    if (gid.x >= width || gid.y >= height) return;

    constexpr int radius = 5;
    constexpr float sigma = 3.0;
    float4 color = float4(0.0);
    float weightSum = 0.0;

    for (int i = -radius; i <= radius; ++i) {
        int y = clamp(int(gid.y) + i, 0, int(height) - 1);
        float w = gaussianWeight(i, sigma);
        color += inTex.read(uint2(gid.x, y)) * w;
        weightSum += w;
    }
    outTex.write(color / weightSum, gid);
}

kernel void sobelEdgeDetection(texture2d<float, access::read>  inTex  [[texture(0)]],
                               texture2d<float, access::write> outTex [[texture(1)]],
                               uint2 gid [[thread_position_in_grid]])
{
    uint width = outTex.get_width(), height = outTex.get_height();
    if (gid.x >= width || gid.y >= height) return;

    int gx[3][3] = { {-1, 0, 1}, {-2, 0, 2}, {-1, 0, 1} };
    int gy[3][3] = { {-1, -2, -1}, {0, 0, 0}, {1, 2, 1} };

    float sampleLum[3][3];
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            int sx = clamp(int(gid.x) + x, 0, int(width) - 1);
            int sy = clamp(int(gid.y) + y, 0, int(height) - 1);
            float3 rgb = inTex.read(uint2(sx, sy)).rgb;
            sampleLum[y + 1][x + 1] = dot(rgb, float3(0.299, 0.587, 0.114));
        }
    }

    float sumX = 0.0, sumY = 0.0;
    for (int y = 0; y < 3; ++y)
        for (int x = 0; x < 3; ++x) {
            sumX += sampleLum[y][x] * float(gx[y][x]);
            sumY += sampleLum[y][x] * float(gy[y][x]);
        }

    float intensity = length(float2(sumX, sumY));
    outTex.write(float4(intensity, intensity, intensity, 1.0), gid);
}
