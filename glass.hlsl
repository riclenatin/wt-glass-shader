// Glass look for Windows Terminal (profile: useAcrylic + opacity < 100).
//
// Layers, bottom to top (premultiplied alpha):
//   XAML: acrylic blur + backgroundImage  (drawn by the Terminal, not here)
//   1. TINT     black veil: acrylic never gets darker than ~#222 on its own
//   2. glass    edge glow (Fresnel) + diagonal sheen
//   3. content  terminal text; cell backgrounds painted by programs (vim, btop,
//               TUI panels) are turned see-through via color-to-alpha against BG
//   4. rim      thin specular edge, lit from the top-left
//
// Static on purpose: do not read Time. The Terminal reflects the compiled shader
// and redraws every frame when Time is used; without it, frames are drawn only
// when the content changes. Background arrives as (0,0,0,0) with acrylic and a
// backgroundImage, so BG below has to be set by hand.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings {
    float  Time;       // unused, see above
    float  Scale;      // display scaling: 1.0 = 100%, 1.5 = 150%
    float2 Resolution; // px
    float4 Background; // unused, see above
};

// Veil over the acrylic. Average acrylic is ~#222222, so 0.53 lands near #101010.
#define TINT 0.53
// What the empty background looks like on screen after the veil; panels are
// split against it, so over a plain background they keep their exact color.
static const float3 BG = float3(0x10, 0x10, 0x10) / 255.0;

#define GLOW_WIDTH   48.0   // px, Fresnel band along the edges
#define GLOW         0.07   // white at the very edge
#define SHEEN        0.035  // top-left diagonal sheen
#define RIM_WIDTH    1.25   // px
#define RIM          0.45   // brightest rim point

// Panels at least this opaque (text, bright bars) become fully opaque.
#define SOLID_FROM 0.25
#define SOLID_TO   0.60

static const float3 LUMA = float3(0.2126, 0.7152, 0.0722);

// Opaque cells (alpha 1): split into BG + translucent layer. Default-background
// pixels (alpha 0) and text on them (partial alpha) pass through unchanged.
float4 seeThrough(float4 c)
{
    if (c.a < 0.999)
        return c;
    if (dot(c.rgb, LUMA) <= dot(BG, LUMA))
        return float4(0, 0, 0, 0);
    float3 d = c.rgb > BG ? (c.rgb - BG) / (1.0 - BG) : (BG - c.rgb) / BG;
    float a = max(d.r, max(d.g, d.b));
    a = max(a, smoothstep(SOLID_FROM, SOLID_TO, a));
    return float4(a * BG + (c.rgb - BG), a);
}

float4 over(float4 top, float4 bottom)
{
    return top + (1.0 - top.a) * bottom;
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float s = max(Scale, 1.0);
    float2 p = tex * Resolution;
    float4 e = float4(p.y, p.x, Resolution.y - p.y, Resolution.x - p.x); // top, left, bottom, right
    float d = min(min(e.x, e.y), min(e.z, e.w));

    // 1-2. veil + glass
    float glow = GLOW * pow(1.0 - smoothstep(0.0, GLOW_WIDTH * s, d), 2.0);
    float sheen = SHEEN * (1.0 - smoothstep(0.0, 0.9, (tex.x + tex.y) * 0.5));
    float g = saturate(glow + sheen);
    float4 glass = over(float4(g, g, g, g), float4(0, 0, 0, TINT));

    // 3. content
    float4 color = over(seeThrough(shaderTexture.Sample(samplerState, tex)), glass);

    // 4. rim: brightest at the top-left and bottom-right corners
    float4 w = RIM * float4(1.0 - 0.6 * tex.x, 0.8 - 0.5 * tex.y, 0.35 + 0.4 * tex.x, 0.3 + 0.4 * tex.y);
    float4 edge = w * (1.0 - smoothstep(0.0, RIM_WIDTH * s, e));
    float r = max(max(edge.x, edge.y), max(edge.z, edge.w));
    return over(float4(r, r, r, r), color);
}
