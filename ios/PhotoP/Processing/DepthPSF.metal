#include <metal_stdlib>
using namespace metal;

// Pixel-center coordinates follow CIImageProcessor's region, including tile ROI.
// Normalized positive taps preserve DC and premultiplied RGB/coverage together.
kernel void photopDepthPSF(texture2d<float, access::sample> source [[texture(0)]],
                          texture2d<float, access::write> destination [[texture(1)]],
                          constant float4 *p [[buffer(0)]], constant float4 *taps [[buffer(1)]],
                          uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) return;
    constexpr sampler linear(coord::pixel, address::clamp_to_edge, filter::linear);
    float2 world = float2(gid) + 0.5f + p[0].zw;
    float2 radial = (world - p[1].xy) / max(1.0f, p[1].z);
    float rr = dot(radial, radial);
    float2 axis = radial * rsqrt(max(1.e-8f, rr));
    float squeeze = min(0.4f, rr * p[2].x);
    float4 sum = 0.0f;
    for (uint i = 0; i < uint(p[2].y); ++i) {
        float2 offset = taps[i].xy;
        offset -= axis * dot(offset, axis) * squeeze;
        sum += source.sample(linear, world - p[0].xy + offset * p[1].w) * taps[i].z;
    }
    destination.write(sum, gid);
}
