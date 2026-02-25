#include <metal_stdlib>
using namespace metal;

[[stitchable]] half4 nebulaEffect(float2 position, half4 color, float2 size, float time) {
    float2 uv = position / size;

    float3 col = float3(0.0);

    float2 p = uv * 3.0 - 1.5;

    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float2 q = p * (1.0 + fi * 0.3);
        q.x += sin(q.y * 2.1 + time * 0.15 + fi * 1.2) * 0.4;
        q.y += cos(q.x * 1.8 + time * 0.12 + fi * 0.9) * 0.4;
        float d = length(q);
        float intensity = 0.008 / (d + 0.01);
        float3 tint = float3(
            0.15 + 0.1 * sin(fi * 2.0 + time * 0.1),
            0.08 + 0.05 * cos(fi * 1.5 + time * 0.08),
            0.25 + 0.15 * sin(fi * 0.7 + time * 0.12)
        );
        col += tint * intensity * 0.06;
    }

    float2 np = uv * 8.0;
    float n = fract(sin(dot(floor(np), float2(127.1, 311.7))) * 43758.5453);
    float sparkle = step(0.997, n) * (0.3 + 0.2 * sin(time * 3.0 + n * 100.0));
    col += float3(sparkle);

    col = clamp(col, 0.0, 1.0);
    return half4(half3(col), 1.0h);
}

[[stitchable]] half4 shimmerGlow(float2 position, half4 color, float2 size, float time) {
    float2 uv = position / size;

    float wave = sin(uv.x * 6.0 + time * 1.5) * 0.5 + 0.5;
    wave *= sin(uv.y * 4.0 + time * 0.8) * 0.5 + 0.5;

    float glow = wave * 0.15;

    half4 result = color;
    result.rgb += half3(glow * 0.3h, glow * 0.15h, glow * 0.6h);
    return result;
}

[[stitchable]] float2 breatheDistortion(float2 position, float time, float2 size) {
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    float2 delta = uv - center;
    float dist = length(delta);

    float pulse = sin(time * 0.8) * 0.003;
    float2 offset = delta * pulse * (1.0 - dist);

    return position + offset * size;
}

// MARK: - Particle Orb Bloom

[[stitchable]] half4 particleGlow(float2 position, half4 color, float time) {
    half luminance = dot(color.rgb, half3(0.299h, 0.587h, 0.114h));

    // Soft bloom for white particles
    half bloomThreshold = 0.08h;
    half bloomAmount = max(luminance - bloomThreshold, 0.0h) * 1.5h;

    half4 result = color;
    result.rgb += bloomAmount * half3(1.0h, 1.0h, 1.0h) * 0.4h;

    result.rgb = clamp(result.rgb, half3(0.0h), half3(1.0h));
    return result;
}

[[stitchable]] half4 auroraWash(float2 position, half4 color, float2 size, float time) {
    float2 uv = position / size;

    float r = 0.02 * sin(uv.x * 3.0 + uv.y * 2.0 + time * 0.3);
    float g = 0.015 * sin(uv.x * 2.5 - uv.y * 3.0 + time * 0.25 + 1.0);
    float b = 0.04 * sin(uv.x * 1.5 + uv.y * 4.0 + time * 0.35 + 2.0);

    float mask = smoothstep(0.0, 0.5, uv.y) * smoothstep(1.0, 0.6, uv.y);

    half4 result = color;
    result.r += half(r * mask);
    result.g += half(g * mask);
    result.b += half(b * mask);
    return result;
}
