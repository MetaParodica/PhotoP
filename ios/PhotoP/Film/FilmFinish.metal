#include <metal_stdlib>
using namespace metal;
struct FilmParameters { float4 values; uint2 size; uint2 padding; };
constant int2 filmOffsets[] = {int2(-1,-1),int2(0,-1),int2(1,-1),int2(-1,0),int2(1,0),int2(-1,1),int2(0,1),int2(1,1)};
static float3 filmHighlight(float4 p) {
    if (p.a == 0) return float3(0);
    float3 rgb = p.rgb / p.a;
    return rgb * clamp((max(rgb.r, max(rgb.g, rgb.b)) - 0.7f) / 0.3f, 0.0f, 1.0f);
}
static float4 finishFilm(float4 rgba, float3 glow, uint2 position, constant FilmParameters &p) {
    if (rgba.a == 0) return rgba;
    float3 color = rgba.rgb / rgba.a;
    color = mix(color, float3(0.5f), p.values.x * 0.25f);
    float2 uv = (float2(position) + 0.5f) / float2(p.size);
    float radius = length(uv * 2.0f - 1.0f);
    color *= 1.0f - p.values.y * 0.8f * smoothstep(0.2f, 1.2f, radius);
    color += glow * p.values.z * 0.25f;
    float halo = dot(glow, float3(0.2126f, 0.7152f, 0.0722f)) * p.values.w * 0.25f;
    color += float3(halo, halo * 0.15f, 0);
    return float4(clamp(color, 0.0f, 1.0f) * rgba.a, rgba.a);
}
kernel void photoPFilmBuffer(device const uchar4 *source [[buffer(0)]], device uchar4 *output [[buffer(1)]],
                             constant FilmParameters &p [[buffer(2)]], uint i [[thread_position_in_grid]]) {
    if (i >= p.size.x * p.size.y) return;
    uint2 q(i % p.size.x, i / p.size.x);
    int radius = max(1, int(round(float(max(p.size.x, p.size.y)) * 2.0f / 1024.0f)));
    float3 glow(0);
    if (p.values.z > 0 || p.values.w > 0) for (uint k = 0; k < 8; ++k) {
        int2 v = clamp(int2(q) + filmOffsets[k] * radius, int2(0), int2(p.size) - 1);
        glow += filmHighlight(float4(source[v.y * p.size.x + v.x]) / 255.0f) / 8.0f;
    }
    output[i] = uchar4(round(finishFilm(float4(source[i]) / 255.0f, glow, q, p) * 255.0f));
}
kernel void photoPFilmTexture(texture2d<float, access::read> source [[texture(0)]], texture2d<float, access::write> output [[texture(1)]],
                              constant FilmParameters &p [[buffer(0)]], uint2 q [[thread_position_in_grid]]) {
    if (q.x >= p.size.x || q.y >= p.size.y) return;
    int radius = max(1, int(round(float(max(p.size.x, p.size.y)) * 2.0f / 1024.0f)));
    float3 glow(0);
    if (p.values.z > 0 || p.values.w > 0) for (uint k = 0; k < 8; ++k) {
        int2 v = clamp(int2(q) + filmOffsets[k] * radius, int2(0), int2(p.size) - 1);
        glow += filmHighlight(source.read(uint2(v))) / 8.0f;
    }
    output.write(finishFilm(source.read(q), glow, q, p), q);
}
