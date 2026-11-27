#version 330

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:screenui_fx.glsl>
#moj_import <minecraft:matrix.glsl>

uniform sampler2D Sampler0;

in float sphericalVertexDistance;
in float cylindricalVertexDistance;
in vec4 vertexColor;
in vec4 lightMapColor;
in vec4 overlayColor;
in vec2 texCoord0;
// CustomPortals: стиль портала end.
in vec4 tintColor;
in vec4 texProj0;

in vec3 screenuiView;
flat in int screenuiLit;

// ScreenUI: light of a screen element by its surface normal - taken from how the view-space position changes
// between neighbour pixels, so it is right whatever space the vertex normals are in. The side facing the viewer:
// a flat icon gets full brightness, a block a lighter top and darker sides, as in the inventory.
float screenui_light() {
    vec3 n = normalize(cross(dFdx(screenuiView), dFdy(screenuiView)));
    if (dot(n, screenuiView) > 0.0) {
        n = -n;
    }
    float light = max(0.0, dot(normalize(vec3(-0.4, 1.0, 0.7)), n)) + max(0.0, dot(normalize(vec3(0.4, 1.0, 0.7)), n));
    return min(1.0, light * 0.6 + 0.4);
}

out vec4 fragColor;

// ── CustomPortals: пиксели customportals:block/portal_end рисуются эффектом портала в Энд ──
const float END_CENTER = 0.2;
const float END_RADIUS = 0.2;
const float END_FINE = 16.0;
// Цикл анимации текстуры в тиках (кадры × frametime) и длина суток, за которые ванильный GameTime проходит 0→1.
const float END_CYCLE = 512.0 * 20.0;
const float DAY = 24000.0;
const int PORTAL_LAYERS = 15;
const float TAU = 6.28318530718;

const vec3[] COLORS = vec3[](
    vec3(0.022087, 0.098399, 0.110818),
    vec3(0.011892, 0.095924, 0.089485),
    vec3(0.027636, 0.101689, 0.100326),
    vec3(0.046564, 0.109883, 0.114838),
    vec3(0.064901, 0.117696, 0.097189),
    vec3(0.063761, 0.086895, 0.123646),
    vec3(0.084817, 0.111994, 0.166380),
    vec3(0.097489, 0.154120, 0.091064),
    vec3(0.106152, 0.131144, 0.195191),
    vec3(0.097721, 0.110188, 0.187229),
    vec3(0.133516, 0.138278, 0.148582),
    vec3(0.070006, 0.243332, 0.235792),
    vec3(0.196766, 0.142899, 0.214696),
    vec3(0.047281, 0.315338, 0.321970),
    vec3(0.204675, 0.390010, 0.302066),
    vec3(0.080955, 0.314821, 0.661491)
);

const mat4 SCALE_TRANSLATE = mat4(
    0.5, 0.0, 0.0, 0.25,
    0.0, 0.5, 0.0, 0.25,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0
);

/** Метка пикселя данных: 0 — не наш, 1 — чётный столбец (медленная фаза), 2 — нечётный (быстрая). */
int endMarker(vec4 c) {
    if (c.a < 0.99) {
        return 0;
    }
    if (abs(length(c.gb - END_CENTER) - END_RADIUS) > 0.03) {
        return 0;
    }
    float r = c.r * 255.0;
    return abs(r - 3.0) < 0.5 ? 1 : abs(r - 5.0) < 0.5 ? 2 : 0;
}

float phase(vec4 c) {
    vec2 p = c.gb - END_CENTER;
    return fract(atan(p.y, p.x) / TAU + 1.0);
}

float hash(vec2 p) {
    uvec2 q = uvec2(mod(p, 256.0));
    uint h = q.x * 73856093u ^ q.y * 19349663u;
    h ^= h >> 13;
    h *= 1274126177u;
    h ^= h >> 16;
    return float(h & 0xFFFFu) / 65535.0;
}

/** Замена end_portal.png: редкие одиночные звёзды на сетке 256×256, бесшовно с периодом 1. */
vec3 stars(vec4 proj) {
    vec2 p = floor(fract(proj.xy / proj.w) * 256.0);
    float h = hash(p);
    return vec3(h > 0.985 ? 0.6 + 0.4 * hash(p + vec2(91.0, 37.0)) : 0.0);
}

/** Замена end_sky.png: фиолетовый шум 128×128. */
vec3 sky(vec4 proj) {
    vec2 p = floor(fract(proj.xy / proj.w) * 128.0);
    return vec3(0.42, 0.32, 0.68) * (0.55 + 0.45 * hash(p + vec2(13.0, 7.0)));
}

/**
 * Как end_portal_layer в rendertype_end_portal.fsh, но сдвиг по y — целое чётное число
 * периодов за цикл (SCALE_TRANSLATE делит его на 2), иначе на стыке цикла слои прыгали бы.
 * Скорость — ближайшая к ванильной.
 */
mat4 end_portal_layer(float layer, float t) {
    float turns = 2.0 * max(1.0, floor((2.0 + layer / 1.5) * 1.5 * END_CYCLE / DAY / 2.0 + 0.5));
    mat4 translate = mat4(
        1.0, 0.0, 0.0, 17.0 / layer,
        0.0, 1.0, 0.0, turns * t,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    );

    mat2 rotate = mat2_rotate_z(radians((layer * layer * 4321.0 + layer * 9.0) * 2.0));

    mat2 scale = mat2((4.5 - layer / 4.0) * 2.0);

    return mat4(scale * rotate) * translate * SCALE_TRANSLATE;
}

vec3 endPortal(float t) {
    vec3 color = sky(texProj0) * COLORS[0];
    for (int i = 0; i < PORTAL_LAYERS; i++) {
        color += stars(texProj0 * end_portal_layer(float(i + 1), t)) * COLORS[i];
    }
    // Берём только оттенок tint, без яркости: серые (белый, чёрный) — ванильные цвета,
    // насыщенные — яркость эффекта в этом оттенке.
    vec3 tint = tintColor.rgb;
    float hi = max(tint.r, max(tint.g, tint.b));
    float amount = hi < 0.001 ? 0.0 : (hi - min(tint.r, min(tint.g, tint.b))) / hi;
    float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return mix(color, lum * (tint / max(hi, 0.001)) * 2.5, amount);
}


void main() {
    // Производные (dFdx) — до ветвления портала.
    float screenuiShade = screenui_light();
    // Уровень 0: на мипах соседние столбцы смешались бы и данные испортились.
    vec4 data = textureLod(Sampler0, texCoord0, 0.0);
    int marker = endMarker(data);
    if (marker != 0) {
        // Пара соседних столбцов: чётный + следующий нечётный (он всегда внутри спрайта 16 px).
        float dx = 1.0 / float(textureSize(Sampler0, 0).x);
        vec4 other = textureLod(Sampler0, texCoord0 + vec2(marker == 1 ? dx : -dx, 0.0), 0.0);
        if (endMarker(other) == 3 - marker) {
            float slow = phase(marker == 1 ? data : other);
            float fine = phase(marker == 1 ? other : data);
            float turn = mod(floor(slow * END_FINE - fine + 0.5), END_FINE);
            float t = (turn + fine) / END_FINE;
            fragColor = apply_fog(vec4(endPortal(t), 1.0), sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
            return;
        }
    }

    vec4 color = texture(Sampler0, texCoord0);
    // ScreenUI: animated backdrops (screenui_fx.glsl).
    if (screenuiLit == 1) {
        color = screenui_backdrop(Sampler0, texCoord0, color, vertexColor);
    }
#ifdef ALPHA_CUTOUT
    if (color.a < ALPHA_CUTOUT) {
        discard;
    }
#endif

    color *= vertexColor * ColorModulator;
    if (screenuiLit == 1) {
        color.rgb *= screenuiShade;
    }
    color.rgb = mix(overlayColor.rgb, color.rgb, overlayColor.a);
    color *= lightMapColor;

    fragColor = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
}
