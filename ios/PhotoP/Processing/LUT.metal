#include <metal_stdlib>
using namespace metal;

struct LUTParameters {
    float4 minimum;
    float4 maximum;
    uint dimension;
    float intensity;
    uint pixelCount;
    uint padding;
    uint width;
    uint height;
    float grainAmount;
    uint grainSeed;
};

static float3 entry(device const float4 *table, uint3 p, uint n) {
    return table[p.x + p.y * n + p.z * n * n].rgb;
}

static float grainValue(uint2 q, uint seed) {
    uint h = q.x * 1664525u + q.y * 1013904223u + seed;
    h = (h ^ (h >> 16)) * 1664525u + 1013904223u;
    h ^= h >> 13;
    return float(h & 65535u) / 32767.5f - 1.0f;
}

static float grainNoise(uint2 position, constant LUTParameters &p) {
    float2 q = (float2(position) + 0.5f) * (512.0f / float(max(p.width, p.height)));
    uint2 low = uint2(floor(q));
    float2 t = fract(q); t = t * t * (3.0f - 2.0f * t);
    return mix(mix(grainValue(low, p.grainSeed), grainValue(low + uint2(1, 0), p.grainSeed), t.x),
               mix(grainValue(low + uint2(0, 1), p.grainSeed), grainValue(low + uint2(1, 1), p.grainSeed), t.x), t.y);
}

static float4 applyLUT(float4 rgba, uint2 position, device const float4 *table, constant LUTParameters &p) {
    if (p.intensity == 0.0f && p.grainAmount == 0.0f) return rgba;
    if (rgba.a == 0.0f) return float4(0);
    float3 input = rgba.rgb / rgba.a;
    float3 coordinate = clamp((input - p.minimum.rgb) / (p.maximum.rgb - p.minimum.rgb), 0.0f, 1.0f) * float(p.dimension - 1);
    uint3 low = uint3(floor(coordinate));
    uint3 high = min(low + 1, uint3(p.dimension - 1));
    float3 t = coordinate - float3(low);
    float3 back = mix(mix(entry(table, uint3(low.x, low.y, low.z), p.dimension), entry(table, uint3(high.x, low.y, low.z), p.dimension), t.x),
                      mix(entry(table, uint3(low.x, high.y, low.z), p.dimension), entry(table, uint3(high.x, high.y, low.z), p.dimension), t.x), t.y);
    float3 front = mix(mix(entry(table, uint3(low.x, low.y, high.z), p.dimension), entry(table, uint3(high.x, low.y, high.z), p.dimension), t.x),
                       mix(entry(table, uint3(low.x, high.y, high.z), p.dimension), entry(table, uint3(high.x, high.y, high.z), p.dimension), t.x), t.y);
    float3 color = clamp(mix(input, mix(back, front, t.z), p.intensity), 0.0f, 1.0f);
    float luma = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
    float noise = grainNoise(position, p) * p.grainAmount * 0.12f * (4.0f * luma * (1.0f - luma));
    return float4(clamp(color + noise, 0.0f, 1.0f) * rgba.a, rgba.a);
}

kernel void photoPLUT(device const uchar4 *source [[buffer(0)]],
                      device uchar4 *destination [[buffer(1)]],
                      device const float4 *table [[buffer(2)]],
                      constant LUTParameters &p [[buffer(3)]],
                      uint index [[thread_position_in_grid]]) {
    if (index >= p.pixelCount) return;
    destination[index] = uchar4(round(applyLUT(float4(source[index]) / 255.0f, uint2(index % p.width, index / p.width), table, p) * 255.0f));
}

kernel void photoPLUTTexture(texture2d<float, access::read> source [[texture(0)]],
                             texture2d<float, access::write> destination [[texture(1)]],
                             device const float4 *table [[buffer(0)]],
                             constant LUTParameters &p [[buffer(1)]],
                             uint2 position [[thread_position_in_grid]]) {
    if (position.x >= source.get_width() || position.y >= source.get_height()) return;
    destination.write(applyLUT(source.read(position), position, table, p), position);
}

struct PreviewVertex {
    float4 position [[position]];
    float2 uv;
};

vertex PreviewVertex photoPPreviewVertex(uint index [[vertex_id]], constant float2 &scale [[buffer(0)]]) {
    const float2 positions[] = {float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1)};
    const float2 coordinates[] = {float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0)};
    return {float4(positions[index] * scale, 0, 1), coordinates[index]};
}

fragment float4 photoPPreviewFragment(PreviewVertex inputVertex [[stage_in]], texture2d<float> image [[texture(0)]]) {
    constexpr sampler previewSampler(filter::linear, address::clamp_to_edge);
    return image.sample(previewSampler, inputVertex.uv);
}
