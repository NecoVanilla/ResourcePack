#version 330

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:screenui_fx.glsl>

uniform sampler2D Sampler0;

#ifdef DISSOLVE
uniform sampler2D DissolveMaskSampler;
#endif

in float sphericalVertexDistance;
in float cylindricalVertexDistance;
#ifdef PER_FACE_LIGHTING
in vec4 vertexPerFaceColorBack;
in vec4 vertexPerFaceColorFront;
#else
in vec4 vertexColor;
#endif

#ifndef EMISSIVE
in vec4 lightMapColor;
#endif

#ifndef NO_OVERLAY
in vec4 overlayColor;
#endif

in vec2 texCoord0;

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

void main() {
    float screenuiShade = screenui_light();
#ifdef PER_FACE_LIGHTING
    vec4 faceVertexColor = gl_FrontFacing ? vertexPerFaceColorFront : vertexPerFaceColorBack;
#else
    vec4 faceVertexColor = vertexColor;
#endif
    vec4 color = texture(Sampler0, texCoord0);
    // ScreenUI: animated backdrops (screenui_fx.glsl).
    if (screenuiLit == 1) {
        color = screenui_backdrop(Sampler0, texCoord0, color, faceVertexColor);
    }
#ifdef ALPHA_CUTOUT
    if (color.a < ALPHA_CUTOUT) {
        discard;
    }
#endif

#ifdef DISSOLVE
    if (faceVertexColor.a < texture(DissolveMaskSampler, texCoord0).a) {
        discard;
    }
    // The dissolve effect entirely replaces translucency
    faceVertexColor.a = 1.0;
#endif

    color *= faceVertexColor * ColorModulator;
    if (screenuiLit == 1) {
        color.rgb *= screenuiShade;
    }
#ifndef NO_OVERLAY
    color.rgb = mix(overlayColor.rgb, color.rgb, overlayColor.a);
#endif
#ifndef EMISSIVE
    color *= lightMapColor;
#endif

    fragColor = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
}
