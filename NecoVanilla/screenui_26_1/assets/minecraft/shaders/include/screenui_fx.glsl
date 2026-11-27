#version 330

// ScreenUI: animated pictures ("backdrops", UiSession.image). A backdrop pixel carries its effect code in the low two
// bits of red (low) and blue (high): 0 - none, 1 wave, 2 lava, 3 lava fall, 4 water, 5 flicker, 6 star, 7 embers,
// 8 portal particles, 9 dust, 10 spores, 11 sculk souls, 12 bubbles, 13 heat haze, 14 fire. Not in alpha: a texture
// with alpha other than 0/255 is drawn in the late translucent pass, after a translucent dim has written depth over
// it, and vanishes behind the dim. Only models tinted SCREENUI_BACKDROP_TINT (254, 254, 254 - the tint of the item
// model's layer) are decoded, so ordinary icons never are. Read with texelFetch at mip 0, so mipmaps never blend
// the marks. A pixel of a backdrop is one texel; a block is 16 texels (waves and flicker go per block).

#moj_import <minecraft:globals.glsl>

float screenui_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// One particle per grid cell of g texels; the field slides by v texels a second, each particle sways sideways.
float screenui_particles(vec2 tc, float t, float g, vec2 v, float radius, float density) {
    vec2 p = tc - v * t;
    vec2 cell = floor(p / g);
    if (screenui_hash(cell + 17.0) > density) {
        return 0.0;
    }
    vec2 at = (cell + 0.2 + 0.6 * vec2(screenui_hash(cell), screenui_hash(cell + 7.1))) * g;
    at.x += sin(t * 0.9 + screenui_hash(cell + 3.3) * 6.28) * 2.0;
    float twinkle = 0.55 + 0.45 * sin(t * 3.0 + screenui_hash(cell + 9.2) * 6.28);
    return smoothstep(radius, radius * 0.4, length(p - at)) * twinkle;
}

int screenui_code(vec4 texel) {
    ivec3 bits = ivec3(texel.rgb * 255.0 + 0.5) & 3;
    return bits.r | bits.b << 2;
}

// The texel dx to the side, if it carries the same effect; otherwise the texel's own colour. A plant is baked over
// the dark back wall, so a texel of the wall pulled into its edge would show as a black hole in the leaf.
vec3 screenui_shifted(sampler2D tex, vec2 tc, float dx, vec3 own, int code) {
    vec4 s = texelFetch(tex, ivec2(tc + vec2(dx, 0.0)), 0);
    return s.a < 1.0 || screenui_code(s) != code ? own : s.rgb;
}

// Tint of a backdrop model (the item model layer tint).
const vec3 SCREENUI_BACKDROP_TINT = vec3(254.0 / 255.0);

vec4 screenui_backdrop(sampler2D tex, vec2 uv, vec4 color, vec4 tint) {
    vec2 tc = uv * vec2(textureSize(tex, 0));
    vec4 raw = texelFetch(tex, ivec2(tc), 0);
    if (raw.a == 0.0) {
        discard;
    }
    if (any(greaterThan(abs(tint.rgb - SCREENUI_BACKDROP_TINT), vec3(0.5 / 255.0))) || raw.a < 1.0) {
        return color;
    }
    int code = screenui_code(raw);
    if (code < 1 || code > 14) {
        return color;
    }
    float t = GameTime * 1200.0;
    vec2 block = floor(tc / 16.0);
    vec3 c = raw.rgb;
    if (code == 1) {
        // Vines and leaves sway by up to a texel, each block on its own beat.
        float s = sin(t * 1.6 + block.x * 1.3 + block.y * 0.7 + tc.y * 0.08);
        c = screenui_shifted(tex, tc, floor(s * 1.6 + 0.5), c, 1);
    } else if (code == 2) {
        // Lava pool: one slow swell rolls across the surface (a single wave, so no checkerboard).
        c *= 0.94 + 0.1 * sin(tc.x * 0.12 - tc.y * 0.04 - t * 1.4);
    } else if (code == 3) {
        // Lava fall: the texture slides down, every block of the fall in step. The sprite may sit off the 16-texel
        // grid of the atlas, so read from the fall itself: above its top, take the same texel one block lower.
        vec2 at = vec2(tc.x, max(0.0, tc.y - mod(t * 12.0, 16.0)));
        vec4 s = texelFetch(tex, ivec2(at), 0);
        if (screenui_code(s) != 3) {
            s = texelFetch(tex, ivec2(at + vec2(0.0, 16.0)), 0);
        }
        c = screenui_code(s) == 3 ? s.rgb : c;
        c *= 0.92 + 0.12 * sin(tc.y * 0.13 - t * 4.0);
    } else if (code == 4 || code == 12) {
        float sp = pow(max(0.0, sin(tc.x * 0.15 + t * 1.5) * sin(tc.y * 0.5 - t * 2.3 + tc.x * 0.03)), 10.0);
        c = c * (0.95 + 0.08 * sin(tc.x * 0.2 + t * 2.0)) + vec3(0.55, 0.8, 1.0) * sp * 0.6;
    } else if (code == 5) {
        float h = screenui_hash(block) * 6.28;
        c *= 1.0 + 0.14 * sin(t * 3.1 + h) + 0.06 * sin(t * 7.3 + h * 2.0);
    } else if (code == 14) {
        // Fire: tongues sway more toward their tips, bright bands run up the flame, the block flickers.
        float h = screenui_hash(block) * 6.28;
        float tip = 1.0 - fract(tc.y / 16.0);
        float s = sin(t * 5.0 + h + tc.y * 0.35) * (0.4 + 1.6 * tip);
        c = screenui_shifted(tex, tc, floor(s + 0.5), c, 14);
        c *= 0.9 + 0.22 * sin(tc.y * 0.7 + t * 9.0 + h + sin(tc.x * 0.5 + t * 2.0))
                + 0.08 * sin(t * 7.3 + h * 2.0);
    } else if (code == 6) {
        c *= 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 2.4 + screenui_hash(floor(tc)) * 6.28));
    }
    if (code == 13) {
        // Heat over lava: the wall wobbles, embers rise.
        c = screenui_shifted(tex, tc, floor(sin(t * 5.0 + tc.y * 0.4) * 1.2 + 0.5), c, 13);
    }
    if (code == 7 || code == 13) {
        c += vec3(1.0, 0.6, 0.15) * screenui_particles(tc, t, 22.0, vec2(0.0, -14.0), 1.6, 0.35);
        c = mix(c, vec3(0.45, 0.42, 0.4), screenui_particles(tc, t, 30.0, vec2(3.0, 6.0), 1.2, 0.25) * 0.6);
    } else if (code == 8) {
        c += vec3(0.82, 0.45, 1.0) * screenui_particles(tc, t, 24.0, vec2(1.0, -4.0), 1.5, 0.35);
    } else if (code == 9) {
        c = mix(c, vec3(0.92, 0.88, 0.78), screenui_particles(tc, t, 28.0, vec2(1.0, -1.5), 1.1, 0.3) * 0.35);
    } else if (code == 10) {
        c += vec3(0.7, 0.95, 0.45) * screenui_particles(tc, t, 26.0, vec2(1.5, -3.0), 1.3, 0.3) * 0.8;
    } else if (code == 11) {
        c += vec3(0.25, 0.85, 0.9) * screenui_particles(tc, t, 26.0, vec2(0.0, -6.0), 1.4, 0.3);
    } else if (code == 12) {
        float b = screenui_particles(tc, t, 24.0, vec2(0.0, -18.0), 1.8, 0.35);
        c = mix(c, vec3(0.85, 0.95, 1.0), b * 0.7);
    }
    return vec4(c, 1.0);
}
