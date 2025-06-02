#include <metal_stdlib>
using namespace metal;

#define K_EPSILON 1e-5
#define PI 3.14159265359

inline float2 safeNormalize(float2 v) {
    float len = length(v);
    return (len > K_EPSILON) ? (v / len) : float2(0.0);
}

// --- Vertex Input / Output Structures ---
struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// --- Vertex Shader with Magnifying Glass + Wave Warp ---
vertex VertexOut vertexWarp(VertexIn in [[stage_in]],
                            constant float2& viewportSize [[buffer(1)]],
                            constant float& time [[buffer(2)]]) {
    VertexOut out;
    float2 normPos = in.position.xy;

    float2 center = float2(0.0, 0.0);
    float radius = 0.5;
    float strength = 0.3;
    float dist = distance(normPos, center);

    if (dist < radius) {
        float factor = 1.0 - smoothstep(0.0, radius, dist);
        normPos += safeNormalize(normPos - center) * factor * strength;
    }

    float waveAmplitude = 0.05;
    float waveFrequency = 10.0;
    normPos.y += sin(normPos.x * waveFrequency + time * 5.0) * waveAmplitude;

    out.position = float4(normPos, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

// --- Fragment Shader with Basic + Advanced Effects ---

inline float rand(float2 co) {
    return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
}

fragment float4 fragmentEffects(VertexOut in [[stage_in]],
                                texture2d<float, access::sample> inputTexture [[texture(0)]],
                                constant float& time [[buffer(0)]],
                                constant int& filterIndex [[buffer(1)]],
                                sampler samp [[sampler(0)]]) {
    float2 uv = in.texCoord;
    float2 resolution = float2(inputTexture.get_width(), inputTexture.get_height());

    float4 color = inputTexture.sample(samp, uv);

    // --- Basic Filters ---
    switch (filterIndex) {
        case 0: // None (original)
            break;

        case 1: { // Grayscale
            float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
            color = float4(gray, gray, gray, color.a);
            break;
        }
        case 2: { // Invert
            color = float4(1.0 - color.rgb, color.a);
            break;
        }
        case 3: { // Sepia
            float3 sepia = float3(
                dot(color.rgb, float3(0.393, 0.769, 0.189)),
                dot(color.rgb, float3(0.349, 0.686, 0.168)),
                dot(color.rgb, float3(0.272, 0.534, 0.131))
            );
            color = float4(min(sepia, float3(1.0)), color.a);
            break;
        }
        case 4: { // Brightness +0.2
            color.rgb += 0.2;
            break;
        }
        case 5: { // Contrast adjustment (+20%)
            float contrast = 1.2;
            color.rgb = (color.rgb - 0.5) * contrast + 0.5;
            break;
        }
        default:
            break;
    }

    // --- Advanced Color Effects ---

    // Chromatic Aberration
    constexpr float aberrationAmount = 0.005;
    float2 offsetR = float2(aberrationAmount, 0.0);
    float2 offsetB = float2(-aberrationAmount, 0.0);

    float r = inputTexture.sample(samp, uv + offsetR).r;
    float g = inputTexture.sample(samp, uv).g;
    float b = inputTexture.sample(samp, uv + offsetB).b;
    float4 chromaColor = float4(r, g, b, 1.0);

    // Reinhard tone mapping
    chromaColor.rgb = chromaColor.rgb / (chromaColor.rgb + float3(1.0));

    // Grain
    float grain = (rand(uv * resolution + floor(time * 10.0)) - 0.5) * 0.05;
    chromaColor.rgb += grain;

    // Vignette
    float2 centered = uv - 0.5;
    float vignette = smoothstep(0.8, 0.5, length(centered));
    chromaColor.rgb *= vignette;

    // Combine basic filter color with advanced color effects
    float4 finalColor = float4(color.rgb * chromaColor.rgb, color.a);

    return float4(clamp(finalColor.rgb, 0.0, 1.0), 1.0);
}

// --- Gaussian Blur (Shared Kernel Logic) ---
inline float gaussianWeight(int i, float sigma) {
    return exp(-float(i * i) / (2.0 * sigma * sigma));
}

// --- Horizontal Blur ---
kernel void gaussianBlurHorizontal(texture2d<float, access::read> inTexture [[texture(0)]],
                                   texture2d<float, access::write> outTexture [[texture(1)]],
                                   uint2 gid [[thread_position_in_grid]]) {
    uint width = outTexture.get_width();
    uint height = outTexture.get_height();
    if (gid.x >= width || gid.y >= height) return;

    constexpr int radius = 5;
    constexpr float sigma = 3.0;
    float4 color = float4(0.0);
    float weightSum = 0.0;

    for (int i = -radius; i <= radius; i++) {
        int x = clamp(int(gid.x) + i, 0, int(width) - 1);
        float weight = gaussianWeight(i, sigma);
        color += inTexture.read(uint2(x, gid.y)) * weight;
        weightSum += weight;
    }

    outTexture.write(color / weightSum, gid);
}

// --- Vertical Blur ---
kernel void gaussianBlurVertical(texture2d<float, access::read> inTexture [[texture(0)]],
                                 texture2d<float, access::write> outTexture [[texture(1)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    uint width = outTexture.get_width();
    uint height = outTexture.get_height();
    if (gid.x >= width || gid.y >= height) return;

    constexpr int radius = 5;
    constexpr float sigma = 3.0;
    float4 color = float4(0.0);
    float weightSum = 0.0;

    for (int i = -radius; i <= radius; i++) {
        int y = clamp(int(gid.y) + i, 0, int(height) - 1);
        float weight = gaussianWeight(i, sigma);
        color += inTexture.read(uint2(gid.x, y)) * weight;
        weightSum += weight;
    }

    outTexture.write(color / weightSum, gid);
}

// --- Sobel Edge Detection ---
kernel void sobelEdgeDetection(texture2d<float, access::read> inTexture [[texture(0)]],
                               texture2d<float, access::write> outTexture [[texture(1)]],
                               uint2 gid [[thread_position_in_grid]]) {
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();

    if (gid.x < 1 || gid.y < 1 || gid.x >= width - 1 || gid.y >= height - 1) {
        outTexture.write(float4(0.0), gid);
        return;
    }

    float3 Gx[3] = {float3(-1, -2, -1), float3(0, 0, 0), float3(1, 2, 1)};
    float3 Gy[3] = {float3(-1, 0, 1), float3(-2, 0, 2), float3(-1, 0, 1)};

    float3 sumX = float3(0.0);
    float3 sumY = float3(0.0);

    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            float3 color = inTexture.read(uint2(gid.x + i, gid.y + j)).rgb;
            sumX += color * Gx[j + 1][i + 1];
            sumY += color * Gy[j + 1][i + 1];
        }
    }

    float3 edge = sqrt(sumX * sumX + sumY * sumY);
    float edgeVal = clamp(dot(edge, float3(0.3333)), 0.0, 1.0);
    outTexture.write(float4(edgeVal, edgeVal, edgeVal, 1.0), gid);
}
