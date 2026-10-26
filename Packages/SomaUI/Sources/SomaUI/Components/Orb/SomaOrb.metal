//
//  SomaOrb.metal
//  SomaUI
//
//  The orb as a body of colour lit from within: large soft fields of the
//  aspect's palette drift inside a clean edge, brightest a little above the
//  centre and deepening toward the rim. No rim light, no specular, no halo:
//  an earlier sphere wrapped in the website's Warp pattern read as a marble
//  planet, and the owner asked for something organic and quiet (2026-10-23).
//
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace soma {

/// A pseudo random value per lattice point, in 0...1.
inline float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

/// Value noise: the lattice's random values, blended with a smoothstep.
inline float valueNoise(float2 s) {
    float2 i = floor(s);
    float2 f = s - i;
    float a = hash(i);
    float b = hash(i + float2(1, 0));
    float c = hash(i + float2(0, 1));
    float d = hash(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Three octaves of value noise: broad shapes only, so the colour reads as
/// fields and never as texture.
inline float fbm3(float2 p) {
    float v = 0.0;
    float a = 0.55;
    for (int i = 0; i < 3; i++) {
        v += a * valueNoise(p);
        p = p * 1.9 + float2(1.7, 9.2);
        a *= 0.45;
    }
    return v / 0.9;
}

inline float3 toLinear(float3 c) { return pow(max(c, 0.0), 2.2); }
inline float3 toSRGB(float3 c) { return pow(clamp(c, 0.0, 1.0), 1.0 / 2.2); }

} // namespace soma

/// One orb, drawn into the whole of the view it is applied to.
///
/// - `size`: the view's size in points.
/// - `radius`: the sphere's radius in points; the square around it stays
///   clear.
/// - `clock`: the weather's time, then the slow turn of the colour fields.
/// - `shape`, `camera`, `falloff`: kept for the call site, unused by this look.
/// - `shading`: `x` sets how much light gathers above the centre; the rest is
///   unused.
/// - `c0` to `c3`: the palette's stops, dark, light, dark, light; `accent`
///   lifts the brightest field.
///
/// Returns a premultiplied colour.
[[ stitchable ]] half4 somaOrb(float2 position, half4 color,
                               float2 size, float radius, float4 clock,
                               float4 shape, float4 camera, float4 shading, float falloff,
                               float3 c0, float3 c1, float3 c2, float3 c3, float3 accent) {
    float t = clock.x * 0.05;
    float turn = clock.y;
    float light = shading.x;

    float2 q = (position - size * 0.5) / radius;
    float r = length(q);

    // The fields turn slowly about the centre, once per turn of the clock.
    float ct = cos(turn);
    float st = sin(turn);
    float2 p = float2(q.x * ct - q.y * st, q.x * st + q.y * ct);

    // Deep, mid and light tones, read off the palette.
    float3 deep = soma::toLinear(mix(mix(c0, c2, 0.5), c1, 0.15));
    float3 mid = soma::toLinear(c1);
    float3 pale = soma::toLinear(mix(mix(c3, accent, 0.5), float3(1.0), 0.25));

    float2 w = p + 0.35 * float2(soma::fbm3(p * 0.9 + t), soma::fbm3(p * 0.9 - t + 3.1)) - 0.17;
    float f = soma::fbm3(w * 1.1 + float2(t * 0.6, -t * 0.4));

    // Mid tone above, deep below, in screen space so the light stays put
    // while the fields turn.
    float3 rgb = mix(mid, deep, smoothstep(-0.9, 1.0, q.y + 0.3 * q.x + 0.35 * (f - 0.5)));
    // Pale fields only away from the rim: one that reached the edge read as
    // a stray bright spot on the outline.
    float inner = 1.0 - smoothstep(0.45, 0.82, r);
    rgb = mix(rgb, pale, smoothstep(0.42, 0.95, f) * 0.6 * inner);
    // Light gathered a little above the centre, deepening toward the rim.
    float2 core = q - float2(-0.1, -0.25);
    rgb *= (1.0 - 0.22 * light) + 0.38 * light * exp(-dot(core, core) * 1.6);
    rgb = mix(rgb, deep, pow(r, 4.0) * 0.45);

    float3 srgb = soma::toSRGB(rgb);
    // A whisper of grain, so the gradients never band.
    srgb += (soma::hash(floor(position) * 0.73 + 0.11) - 0.5) * 0.018;

    float alpha = 1.0 - smoothstep(1.0 - 1.0 / radius, 1.0 + 0.5 / radius, r);
    return half4(half3(clamp(srgb, 0.0, 1.0) * alpha), half(alpha));
}
