#include <metal_stdlib>
using namespace metal;

struct MonitorParameters { uint flags; uint step; float zebra; float peaking; };
static float3 monitorRGB(texture2d<float, access::read> source, int2 p) {
    p = clamp(p, int2(0), int2(source.get_width() - 1, source.get_height() - 1));
    float4 color = source.read(uint2(p));
    return color.a > 0 ? color.rgb / color.a : float3(0);
}
static float monitorLuma(float3 color) { return dot(color, float3(54, 183, 19)) / 256.0f; }
static float3 monitorFalseColor(float y) {
    if (y < 0.03f) return float3(106, 53, 167) / 255;
    if (y < 0.10f) return float3(36, 95, 240) / 255;
    if (y < 0.40f) return float3(89) / 255;
    if (y < 0.60f) return float3(50, 176, 90) / 255;
    if (y < 0.90f) return float3(184) / 255;
    if (y < 0.97f) return float3(244, 207, 69) / 255;
    return float3(234, 68, 59) / 255;
}

kernel void photoPMonitor(texture2d<float, access::read> source [[texture(0)]],
                          texture2d<float, access::read> graded [[texture(1)]],
                          texture2d<float, access::write> overlay [[texture(2)]],
                          device atomic_uint *counts [[buffer(0)]],
                          constant MonitorParameters &p [[buffer(1)]],
                          uint2 position [[thread_position_in_grid]]) {
    if (position.x >= source.get_width() || position.y >= source.get_height()) return;
    float4 result = graded.read(position);
    float3 input = monitorRGB(source, int2(position));
    if ((p.flags & (1u | 8u | 16u | 32u)) && position.x % p.step == 0 && position.y % p.step == 0 && source.read(position).a > 0) {
        uint3 rgb = uint3(round(clamp(input, 0.0f, 1.0f) * 255.0f));
        uint4 bins = uint4(rgb * 64u / 255u, (54u * rgb.r + 183u * rgb.g + 19u * rgb.b) / 1020u);
        for (uint channel = 0; channel < 4 && (p.flags & 1u); ++channel) {
            uint bin = min(bins[channel], 63u);
            atomic_fetch_add_explicit(&counts[channel * 64 + bin], 1u, memory_order_relaxed);
        }
        uint column = min(position.x * 64u / source.get_width(), 63u);
        if (p.flags & 8u) atomic_fetch_add_explicit(&counts[256u + column * 64u + min(bins.w, 63u)], 1u, memory_order_relaxed);
        if (p.flags & 16u) for (uint c = 0; c < 3; ++c) {
            atomic_fetch_add_explicit(&counts[4352u + c * 4096u + column * 64u + min(bins[c], 63u)], 1u, memory_order_relaxed);
        }
        if (p.flags & 32u) {
            float y = monitorLuma(input);
            uint cb = min(uint(clamp((input.b - y) / 1.8556f + 0.5f, 0.0f, 1.0f) * 64 + 1e-5f), 63u);
            uint cr = min(uint(clamp((input.r - y) / 1.5748f + 0.5f, 0.0f, 1.0f) * 64 + 1e-5f), 63u);
            atomic_fetch_add_explicit(&counts[16640u + cr * 64u + cb], 1u, memory_order_relaxed);
        }
    }
    if (result.a == 0) { overlay.write(result, position); return; }
    if ((p.flags & 64u) && source.read(position).a > 0) {
        result.rgb = monitorFalseColor(monitorLuma(input)) * result.a;
        overlay.write(result, position); return;
    }
    bool clipped = (p.flags & 2u) && max(input.r, max(input.g, input.b)) >= p.zebra;
    if (clipped) {
        float3 stripe = (position.x + position.y) % 12 < 6 ? float3(1, 1, 0) : float3(0);
        result.rgb = mix(result.rgb, stripe * result.a, 0.7f);
    } else if (p.flags & 4u) {
        int2 q = int2(position);
        float gx = 0, gy = 0;
        for (int y = -1; y <= 1; ++y) for (int x = -1; x <= 1; ++x) {
            float luma = monitorLuma(monitorRGB(source, q + int2(x, y)));
            gx += luma * float(x * (y == 0 ? 2 : 1));
            gy += luma * float(y * (x == 0 ? 2 : 1));
        }
        if (max(abs(gx), abs(gy)) / 4.0f >= p.peaking) result.rgb = float3(0, result.a, 0);
    }
    overlay.write(result, position);
}
