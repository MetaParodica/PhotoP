#include <metal_stdlib>
using namespace metal;

struct FusionParameters {
    uint width, height;
    int x0, y0, x2, y2;
    float contrast, saturation, exposure;
};
static float3 fusionRGB(const device uchar4 *pixels, int2 q, constant FusionParameters &p) {
    q = clamp(q, int2(0), int2(p.width - 1, p.height - 1));
    return float3(pixels[q.y * p.width + q.x].rgb) / 255.0f;
}
static float fusionY(float3 c) { return dot(c, float3(0.2126f, 0.7152f, 0.0722f)); }
static float fusionWeight(const device uchar4 *pixels, int2 q, constant FusionParameters &p) {
    if (q.x < 0 || q.y < 0 || q.x >= int(p.width) || q.y >= int(p.height)) return 0;
    float weight = 0;
    // Smooth the quality weights, not the source image, to limit hard seams.
    for (int y = -1; y <= 1; ++y) for (int x = -1; x <= 1; ++x) {
        int2 r = q + int2(x, y);
        float3 c = fusionRGB(pixels, r, p);
        float lap = abs(fusionY(fusionRGB(pixels, r + int2(-1, 0), p)) + fusionY(fusionRGB(pixels, r + int2(1, 0), p))
                      + fusionY(fusionRGB(pixels, r + int2(0, -1), p)) + fusionY(fusionRGB(pixels, r + int2(0, 1), p)) - 4 * fusionY(c));
        float average = (c.r + c.g + c.b) / 3;
        float saturation = sqrt(dot(c - average, c - average) / 3);
        float exposure = exp(-dot(c - 0.5f, c - 0.5f) / 0.08f);
        weight += pow(max(lap, 0.001f), p.contrast) * pow(max(saturation, 0.001f), p.saturation) * pow(max(exposure, 0.001f), p.exposure);
    }
    return weight / 9;
}
kernel void photoPExposureFusion(const device uchar4 *dark [[buffer(0)]],
                                 const device uchar4 *center [[buffer(1)]],
                                 const device uchar4 *bright [[buffer(2)]],
                                 device uchar4 *result [[buffer(3)]],
                                 constant FusionParameters &p [[buffer(4)]],
                                 uint index [[thread_position_in_grid]]) {
    if (index >= p.width * p.height) return;
    int2 q = int2(index % p.width, index / p.width);
    int2 a = q + int2(p.x0, p.y0), b = q + int2(p.x2, p.y2);
    float3 weights = float3(fusionWeight(dark, a, p), fusionWeight(center, q, p), fusionWeight(bright, b, p));
    weights /= max(dot(weights, float3(1)), 1e-12f);
    float3 color = fusionRGB(dark, a, p) * weights.x + fusionRGB(center, q, p) * weights.y + fusionRGB(bright, b, p) * weights.z;
    result[index] = uchar4(uchar3(round(clamp(color, 0.0f, 1.0f) * 255)), 255);
}
