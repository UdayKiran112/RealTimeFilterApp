#include <metal_stdlib>
using namespace metal;

#define K_EPSILON 1e-5
#define PI 3.14159265359

// Utility: Safely normalize a 2D vector to avoid division by zero
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

// --- Vertex Shader: Magnifying Glass + Wave Warp Effect ---
vertex VertexOut vertexWarp(VertexIn in [[stage_in]],
                            constant float2& viewportSize [[buffer(1)]],
                            constant float& time [[buffer(2)]]) {
    VertexOut out;
    float2 normPos = in.position.xy;

    // Parameters for magnifying glass effect
    float2 center = float2(0.0, 0.0);
    float radius = 0.5;
    float strength = 0.3;
    float dist = distance(normPos, center);

    // Apply magnifying distortion inside radius
    if (dist < radius) {
        float factor = 1.0 - smoothstep(0.0, radius, dist);
        normPos += safeNormalize(normPos - center) * factor * strength;
    }

    // Add a wave distortion over Y axis based on X and time
    float waveAmplitude = 0.05;
    float waveFrequency = 10.0;
    normPos.y += sin(normPos.x * waveFrequency + time * 5.0) * waveAmplitude;

    out.position = float4(normPos, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

// --- Basic Color Filter Functions ---

// Grayscale filter
float4 filterGrayscale(float4 color) {
    float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
    return float4(gray, gray, gray, color.a);
}

// Invert color filter
float4 filterInvert(float4 color) {
    return float4(1.0 - color.rgb, color.a);
}

// Sepia tone filter
float4 filterSepia(float4 color) {
    float3 sepia = float3(
        dot(color.rgb, float3(0.393, 0.769, 0.189)),
        dot(color.rgb, float3(0.349, 0.686, 0.168)),
        dot(color.rgb, float3(0.272, 0.534, 0.131))
    );
    return float4(min(sepia, float3(1.0)), color.a);
}

// Brightness increase (+0.2)
float4 filterBrightness(float4 color) {
    color.rgb += 0.2;
    return color;
}

// Contrast adjustment (+20%)
float4 filterContrast(float4 color) {
    float contrast = 1.2;
    color.rgb = (color.rgb - 0.5) * contrast + 0.5;
    return color;
}

// --- Random function for grain noise ---
inline float rand(float2 co) {
    return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
}

// --- Main Fragment Shader ---
// Applies basic filters and advanced color effects
fragment float4 fragmentEffects(VertexOut in [[stage_in]],
                                texture2d<float, access::sample> inputTexture [[texture(0)]],
                                constant float& time [[buffer(0)]],
                                constant int& filterIndex [[buffer(1)]],
                                sampler samp [[sampler(0)]]) {
    float2 uv = in.texCoord;
    float2 resolution = float2(inputTexture.get_width(), inputTexture.get_height());

    // Sample the input texture color
    float4 color = inputTexture.sample(samp, uv);

    // Apply selected basic filter based on filterIndex
    switch (filterIndex) {
        case 0: // None (original)
            break;
        case 1: // Grayscale
            color = filterGrayscale(color);
            break;
        case 2: // Invert
            color = filterInvert(color);
            break;
        case 3: // Sepia
            color = filterSepia(color);
            break;
        case 4: // Brightness +0.2
            color = filterBrightness(color);
            break;
        case 5: // Contrast +20%
            color = filterContrast(color);
            break;
        default:
            break;
    }

    // --- Advanced Color Effects ---

    // Chromatic aberration offsets
    constexpr float aberrationAmount = 0.005;
    float2 offsetR = float2(aberrationAmount, 0.0);
    float2 offsetB = float2(-aberrationAmount, 0.0);

    // Sample texture for R, G, B with offsets
    float r = inputTexture.sample(samp, uv + offsetR).r;
    float g = inputTexture.sample(samp, uv).g;
    float b = inputTexture.sample(samp, uv + offsetB).b;
    float4 chromaColor = float4(r, g, b, 1.0);

    // Reinhard tone mapping for HDR-like effect
    chromaColor.rgb = chromaColor.rgb / (chromaColor.rgb + float3(1.0));

    // Grain noise effect (animated with time)
    float grain = (rand(uv * resolution + floor(time * 10.0)) - 0.5) * 0.05;
    chromaColor.rgb += grain;

    // Vignette darkening effect around edges
    float2 centered = uv - 0.5;
    float vignette = smoothstep(0.8, 0.5, length(centered));
    chromaColor.rgb *= vignette;

    // Combine basic filter color with advanced effects multiplicatively
    float4 finalColor = float4(color.rgb * chromaColor.rgb, color.a);

    // Clamp final color to [0,1] range and set alpha to 1.0
    return float4(clamp(finalColor.rgb, 0.0, 1.0), 1.0);
}

// --- Gaussian Blur Helper Function ---
// Computes Gaussian weight for a given offset 'i' with sigma
inline float gaussianWeight(int i, float sigma) {
    return exp(-float(i * i) / (2.0 * sigma * sigma));
}

// --- Gaussian Blur Horizontal Kernel ---
// Performs horizontal blur pass
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

    // Sum weighted colors horizontally
    for (int i = -radius; i <= radius; i++) {
        int x = clamp(int(gid.x) + i, 0, int(width) - 1);
        float weight = gaussianWeight(i, sigma);
        color += inTexture.read(uint2(x, gid.y)) * weight;
        weightSum += weight;
    }

    outTexture.write(color / weightSum, gid);
}

// --- Gaussian Blur Vertical Kernel ---
// Performs vertical blur pass
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

    // Sum weighted colors vertically
    for (int i = -radius; i <= radius; i++) {
        int y = clamp(int(gid.y) + i, 0, int(height) - 1);
        float weight = gaussianWeight(i, sigma);
        color += inTexture.read(uint2(gid.x, y)) * weight;
        weightSum += weight;
    }

    outTexture.write(color / weightSum, gid);
}

// --- Sobel Edge Detection Kernel ---
// Detects edges using Sobel operator on RGB channels
kernel void sobelEdgeDetection(texture2d<float, access::read> inTexture [[texture(0)]],
                               texture2d<float, access::write> outTexture [[texture(1)]],
                               uint2 gid [[thread_position_in_grid]]) {
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();

    // Avoid borders to prevent out-of-bounds
    if (gid.x < 1 || gid.y < 1 || gid.x >= width - 1 || gid.y >= height - 1) {
        outTexture.write(float4(0.0), gid);
        return;
    }

    // Sobel kernels for horizontal (Gx) and vertical (Gy) edge detection
    float3 Gx[3] = {float3(-1, -2, -1), float3(0, 0, 0), float3(1, 2, 1)};
    float3 Gy[3] = {float3(-1, 0, 1), float3(-2, 0, 2), float3(-1, 0, 1)};

    float3 sumX = float3(0.0);
    float3 sumY = float3(0.0);

    // Convolve Sobel kernels with neighboring pixels
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            float3 color = inTexture.read(uint2(gid.x + i, gid.y + j)).rgb;
            sumX += color * Gx[j + 1][i + 1];
            sumY += color * Gy[j + 1][i + 1];
        }
    }

    // Compute gradient magnitude
    float3 edge = sqrt(sumX * sumX + sumY * sumY);
    float edgeVal = clamp(dot(edge, float3(0.3333)), 0.0, 1.0);

    // Output grayscale edge intensity
    outTexture.write(float4(edgeVal, edgeVal, edgeVal, 1.0), gid);
}
