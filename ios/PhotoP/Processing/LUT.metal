#include <metal_stdlib>
using namespace metal;

struct LUTParameters {
    float4 minimum;
    float4 maximum;
    uint dimension;
    float intensity;
    uint pixelCount;
    uint padding;
};

static float3 entry(device const float4 *table, uint3 p, uint n) {
    return table[p.x + p.y * n + p.z * n * n].rgb;
}

kernel void photoPLUT(device const uchar4 *source [[buffer(0)]],
                      device uchar4 *destination [[buffer(1)]],
                      device const float4 *table [[buffer(2)]],
                      constant LUTParameters &p [[buffer(3)]],
                      uint index [[thread_position_in_grid]]) {
    if (index >= p.pixelCount) return;
    uchar4 bytes = source[index];
    if (bytes.a == 0) { destination[index] = uchar4(0); return; }
    float alpha = float(bytes.a) / 255.0f;
    float3 input = float3(bytes.rgb) / float(bytes.a);
    float3 coordinate = clamp((input - p.minimum.rgb) / (p.maximum.rgb - p.minimum.rgb), 0.0f, 1.0f) * float(p.dimension - 1);
    uint3 low = uint3(floor(coordinate));
    uint3 high = min(low + 1, uint3(p.dimension - 1));
    float3 t = coordinate - float3(low);
    float3 back = mix(mix(entry(table, uint3(low.x, low.y, low.z), p.dimension), entry(table, uint3(high.x, low.y, low.z), p.dimension), t.x),
                      mix(entry(table, uint3(low.x, high.y, low.z), p.dimension), entry(table, uint3(high.x, high.y, low.z), p.dimension), t.x), t.y);
    float3 front = mix(mix(entry(table, uint3(low.x, low.y, high.z), p.dimension), entry(table, uint3(high.x, low.y, high.z), p.dimension), t.x),
                       mix(entry(table, uint3(low.x, high.y, high.z), p.dimension), entry(table, uint3(high.x, high.y, high.z), p.dimension), t.x), t.y);
    float3 result = clamp(mix(input, mix(back, front, t.z), p.intensity), 0.0f, 1.0f) * alpha;
    destination[index] = uchar4(uchar3(round(result * 255.0f)), bytes.a);
}
