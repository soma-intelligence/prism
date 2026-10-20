//
//  SomaOrb.metal
//  SomaUI
//
//  The website hero's Warp shader (Paper Shaders, Apache-2.0), wrapped on a
//  sphere lit from the top left, with the aspect's accent as rim and halo.
//
//  A line for line port of the renders in the Figma proposal, which computed
//  the site's GLSL with its own parameters. One change: the site reads its
//  random lattice from a noise texture, and this hashes the lattice instead,
//  so the package ships no image. The weather keeps its character; the exact
//  swirls differ from the site's.
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

/// The Warp fragment shader, shape "checks", ten swirl iterations, on pattern
/// coordinates.
///
/// `shape` is proportion, softness, distortion and swirl; `shapeScale` sizes
/// the checks. `calm`, 0 to 1, smooths the weather: the shapes grow, the
/// distortion eases, and each finer swirl harmonic is damped harder than the
/// site's, so the large flow stays and the small eddies that read as boiling
/// fade. At 0 it is the site's shader unchanged.
inline float3 warp(float2 coordinates, float time, float4 shape, float shapeScale, float calm,
                   float3 c0, float3 c1, float3 c2, float3 c3) {
    float proportion = clamp(shape.x, 0.0, 1.0);
    float softness = shape.y;
    float distortion = shape.z * (1.0 - 0.45 * calm);
    float swirl = shape.w * (1.0 - 0.2 * calm);
    float falloff = 1.0 + 0.7 * calm;

    float2 uv = coordinates * 0.5 * (1.0 - 0.3 * calm);
    float t = 0.0625 * (time + 118.0);
    float n1 = valueNoise(uv + t);
    float n2 = valueNoise(uv * 2.0 - t);
    float angle = n1 * 2.0 * M_PI_F;
    uv += 4.0 * distortion * n2 * float2(cos(angle), sin(angle));

    for (int i = 1; i < 10; i++) {
        float fi = float(i);
        float reach = swirl / pow(fi, falloff);
        uv.x += reach * cos(t + fi * 1.5 * uv.y);
        uv.y += reach * cos(t + fi * 1.0 * uv.x);
    }

    float k = 0.5 + 3.5 * shapeScale;
    float value = 0.5 + 0.5 * sin(uv.x * k) * cos(uv.y * k);
    value += 0.48 * sign(proportion - 0.5) * sqrt(abs(proportion - 0.5));

    float3 colors[4] = { c0, c1, c2, c3 };
    float mixer = value * 3.0;
    float3 gradient = colors[0];
    for (int i = 1; i < 4; i++) {
        float m = clamp(mixer - float(i - 1), 0.0, 1.0);
        float start = floor(m);
        float soft = 0.5 * softness;
        float smooth = smoothstep(max(0.0, 0.5 - soft), min(1.0, 0.5 + soft), m - start);
        m = (start + smooth) * (1.0 - softness) + m * softness;
        gradient = mix(gradient, colors[i], m);
    }
    return gradient;
}

} // namespace soma

/// One orb, drawn into the whole of the view it is applied to.
///
/// - `size`: the view's size in points.
/// - `radius`: the sphere's radius in points; what lies outside it is halo.
/// - `clock`: the weather's time, the sphere's turn, how calm the weather is
///   (0 to 1, see `warp`), and the breath (-1 to 1), which lifts the halo.
/// - `shape`: proportion, softness, distortion, swirl.
/// - `camera`: shape scale, rotation in radians, zoom, detail.
/// - `shading`: light, rim, depth, the halo's strength.
/// - `falloff`: how fast the halo fades past the rim.
/// - `c0` to `c3`: the palette's four stops; `accent`: the rim and halo.
///
/// Returns a premultiplied colour.
[[ stitchable ]] half4 somaOrb(float2 position, half4 color,
                               float2 size, float radius, float4 clock,
                               float4 shape, float4 camera, float4 shading, float falloff,
                               float3 c0, float3 c1, float3 c2, float3 c3, float3 accent) {
    float time = clock.x;
    float spin = clock.y;
    float calm = clamp(clock.z, 0.0, 1.0);
    float breath = clock.w;
    float shapeScale = camera.x;
    float rotation = camera.y;
    float zoom = camera.z;
    float detail = camera.w;
    float light = shading.x;
    float rim = shading.y;
    float depth = shading.z;
    float glow = shading.w * (1.0 + breath);

    float2 q = (position - size * 0.5) / radius;
    float r = length(q);
    float z = sqrt(clamp(1.0 - r * r, 0.0, 1.0));
    float3 normal = float3(q.x, -q.y, z);

    // The sphere turns about its vertical axis.
    float cs = cos(spin);
    float sn = sin(spin);
    float sx = normal.x * cs + normal.z * sn;
    float sz = -normal.x * sn + normal.z * cs;
    float k = 4.2 * detail / zoom;
    float2 u = float2(sx, -normal.y) / (1.5 + sz) * k;
    float cr = cos(rotation);
    float sr = sin(rotation);
    float2 turned = float2(u.x * cr - u.y * sr, u.x * sr + u.y * cr);

    float3 surface = soma::warp(turned, time, shape, shapeScale, calm, c0, c1, c2, c3);
    surface = pow(max(surface, 0.0), depth);

    // Light from the top left, a little in front: the lit side keeps the
    // palette, the far side sinks toward the darkest stop rather than to black.
    float3 toLight = normalize(float3(-0.45, 0.55, 0.7));
    float diffuse = clamp(dot(normal, toLight), 0.0, 1.0);
    surface *= (1.0 - 0.8 * light) + 0.92 * light * diffuse;
    surface += accent * pow(1.0 - z, 2.4) * rim;
    float3 halfway = normalize(toLight + float3(0, 0, 1));
    surface += pow(clamp(dot(normal, halfway), 0.0, 1.0), 36.0) * 0.28 * light;

    float edge = 1.5 / radius;
    float inside = 1.0 - smoothstep(1.0 - edge, 1.0, r);
    float halo = glow * exp(-max(r - 1.0, 0.0) * falloff) * (1.0 - inside);
    float alpha = clamp(inside + halo, 0.0, 1.0);
    float3 rgb = (surface * inside + accent * halo) / max(inside + halo, 1e-5);
    return half4(half3(clamp(rgb, 0.0, 1.0) * alpha), half(alpha));
}
