#include <metal_stdlib>
using namespace metal;

struct FXVertexIn {
    float2 position; // NDC 0..1，原点左上（y 向下），由 CPU 预转
    float4 color;
};

struct FXVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex FXVertexOut fx_vertex(
    const device float *data [[buffer(0)]],
    constant float4 &viewport [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    uint base = vid * 6;
    float x = data[base + 0];
    float y = data[base + 1];
    float r = data[base + 2];
    float g = data[base + 3];
    float b = data[base + 4];
    float a = data[base + 5];

    // 0..1 → NDC（y 翻转）
    float ndcX = x * 2.0 - 1.0;
    float ndcY = 1.0 - y * 2.0;

    FXVertexOut out;
    out.position = float4(ndcX, ndcY, 0.0, 1.0);
    out.color = float4(r, g, b, a);
    return out;
}

fragment float4 fx_fragment(FXVertexOut in [[stage_in]]) {
    return in.color;
}
