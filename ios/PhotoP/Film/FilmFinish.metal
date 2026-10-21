#include <metal_stdlib>
using namespace metal;
struct FilmParameters { float4 values; uint2 size; uint2 padding; float4 advanced; };
constant int2 filmOffsets[] = {int2(-1,-1),int2(0,-1),int2(1,-1),int2(-1,0),int2(1,0),int2(-1,1),int2(0,1),int2(1,1)};
constant int streakOffsets[] = {-8,-4,-2,-1,1,2,4,8};
constant float streakWeights[] = {0.05f,0.10f,0.15f,0.20f,0.20f,0.15f,0.10f,0.05f};
static float3 filmStraight(float4 p) { return p.a > 0 ? p.rgb / p.a : float3(0); }
static float3 filmHighlight(float4 p) {
    float3 rgb = filmStraight(p);
    return rgb * clamp((max(rgb.r, max(rgb.g, rgb.b)) - 0.7f) / 0.3f, 0.0f, 1.0f);
}
static uint2 bounded(int2 q, uint2 size) { return uint2(clamp(q, int2(0), int2(size) - 1)); }
static int2 fringeOffset(uint2 q, constant FilmParameters &p) {
    float2 radial = (float2(q) + 0.5f) / float2(p.size) * 2.0f - 1.0f;
    return int2(round(radial * float(max(p.size.x, p.size.y)) * 0.006f * p.advanced.y));
}
static float4 finishFilm(float4 rgba, float3 glow, float3 softened, float3 fringed, float3 streak, uint2 position, constant FilmParameters &p) {
    if (rgba.a == 0) return rgba;
    float3 color = mix(fringed, softened, p.advanced.x * 0.65f);
    color = mix(color, float3(0.5f), p.values.x * 0.25f);
    float2 uv = (float2(position) + 0.5f) / float2(p.size);
    float radius = length(uv * 2.0f - 1.0f);
    color *= 1.0f - p.values.y * 0.8f * smoothstep(0.2f, 1.2f, radius);
    color += glow * p.values.z * 0.25f;
    float halo = dot(glow, float3(0.2126f, 0.7152f, 0.0722f)) * p.values.w * 0.25f;
    color += float3(halo, halo * 0.15f, 0);
    color += streak * p.advanced.z * 0.25f;
    return float4(clamp(color, 0.0f, 1.0f) * rgba.a, rgba.a);
}
kernel void photoPFilmBuffer(device const uchar4 *source [[buffer(0)]], device uchar4 *output [[buffer(1)]],
                             constant FilmParameters &p [[buffer(2)]], uint i [[thread_position_in_grid]]) {
    if (i >= p.size.x * p.size.y) return;
    uint2 q(i % p.size.x, i / p.size.x);
    float4 center = float4(source[i]) / 255.0f;
    int radius = max(1, int(round(float(max(p.size.x, p.size.y)) * 2.0f / 1024.0f)));
    float3 glow(0), soft = filmStraight(center) / 9.0f, fringe = filmStraight(center), streak(0);
    bool highlights = p.values.z > 0 || p.values.w > 0;
    if (highlights || p.advanced.x > 0) for (uint k = 0; k < 8; ++k) {
        uint2 v = bounded(int2(q) + filmOffsets[k] * radius, p.size);
        float4 sample = float4(source[v.y * p.size.x + v.x]) / 255.0f;
        if (highlights) glow += filmHighlight(sample) / 8.0f;
        if (p.advanced.x > 0) soft += filmStraight(sample) / 9.0f;
    }
    if (p.advanced.y > 0) {
        int2 shift = fringeOffset(q, p);
        uint2 r = bounded(int2(q) + shift, p.size), b = bounded(int2(q) - shift, p.size);
        fringe.r = filmStraight(float4(source[r.y * p.size.x + r.x]) / 255.0f).r;
        fringe.b = filmStraight(float4(source[b.y * p.size.x + b.x]) / 255.0f).b;
    }
    if (p.advanced.z > 0) for (uint k = 0; k < 8; ++k) {
        uint2 v = bounded(int2(q) + int2(streakOffsets[k] * radius, 0), p.size);
        streak += filmHighlight(float4(source[v.y * p.size.x + v.x]) / 255.0f) * streakWeights[k];
    }
    output[i] = uchar4(round(finishFilm(center, glow, soft, fringe, streak, q, p) * 255.0f));
}
kernel void photoPFilmTexture(texture2d<float, access::read> source [[texture(0)]], texture2d<float, access::write> output [[texture(1)]],
                              constant FilmParameters &p [[buffer(0)]], uint2 q [[thread_position_in_grid]]) {
    if (q.x >= p.size.x || q.y >= p.size.y) return;
    float4 center = source.read(q);
    int radius = max(1, int(round(float(max(p.size.x, p.size.y)) * 2.0f / 1024.0f)));
    float3 glow(0), soft = filmStraight(center) / 9.0f, fringe = filmStraight(center), streak(0);
    bool highlights = p.values.z > 0 || p.values.w > 0;
    if (highlights || p.advanced.x > 0) for (uint k = 0; k < 8; ++k) {
        float4 sample = source.read(bounded(int2(q) + filmOffsets[k] * radius, p.size));
        if (highlights) glow += filmHighlight(sample) / 8.0f;
        if (p.advanced.x > 0) soft += filmStraight(sample) / 9.0f;
    }
    if (p.advanced.y > 0) {
        int2 shift = fringeOffset(q, p);
        fringe.r = filmStraight(source.read(bounded(int2(q) + shift, p.size))).r;
        fringe.b = filmStraight(source.read(bounded(int2(q) - shift, p.size))).b;
    }
    if (p.advanced.z > 0) for (uint k = 0; k < 8; ++k) {
        streak += filmHighlight(source.read(bounded(int2(q) + int2(streakOffsets[k] * radius, 0), p.size))) * streakWeights[k];
    }
    output.write(finishFilm(center, glow, soft, fringe, streak, q, p), q);
}
