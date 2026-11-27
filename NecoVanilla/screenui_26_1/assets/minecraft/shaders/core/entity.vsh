#version 330

#moj_import <minecraft:light.glsl>
#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:projection.glsl>
#moj_import <minecraft:sample_lightmap.glsl>

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV1;
in ivec2 UV2;
in vec3 Normal;

#ifndef NO_OVERLAY
uniform sampler2D Sampler1;
#endif

#ifndef EMISSIVE
uniform sampler2D Sampler2;
#endif

out float sphericalVertexDistance;
out float cylindricalVertexDistance;

#ifdef PER_FACE_LIGHTING
out vec4 vertexPerFaceColorBack;
out vec4 vertexPerFaceColorFront;
#else
out vec4 vertexColor;
#endif

#ifndef EMISSIVE
out vec4 lightMapColor;
#endif

#ifndef NO_OVERLAY
out vec4 overlayColor;
#endif

out vec2 texCoord0;

// ScreenUI: the screen is drawn as if the client's FOV were 70, whatever the setting.
// Screen displays have light block 15 / sky 14 (UV2 = 240, 224) and sit 0.5-2 blocks in front of the camera.
// pack-cursor: light block 15 / sky 13 (UV2 = 240, 208) - the player looks at the screen with their own eyes and
// turns their head freely. The screen (0.3-3 blocks south of the camera) is drawn from a fixed camera that faces
// south at FOV 70, whatever the head rotation; its 16:9 area always fits the window (a narrower one shrinks it).
vec4 screenui_fov(vec4 clip) {
    if (ProjMat[3][3] == 0.0) {
        if (UV2 == ivec2(240, 224) && clip.w > 0.5 && clip.w < 2.0) {
            clip.xy *= 1.4281480 / ProjMat[1][1]; // 1 / tan(70 deg / 2)
        } else if (UV2 == ivec2(240, 208) && Position.z > 0.3 && Position.z < 3.0
                && abs(Position.x) < 8.0 && abs(Position.y) < 6.0) {
            float aspect = ProjMat[1][1] / ProjMat[0][0];
            float fit = min(1.0, aspect / 1.7777778); // 16:9
            vec3 v = vec3(-Position.x, Position.y, -Position.z);
            clip = vec4(v.x * 1.4281480 * fit / aspect, v.y * 1.4281480 * fit,
                        ProjMat[2][2] * v.z + ProjMat[3][2], ProjMat[2][3] * v.z);
        }
    }
    return clip;
}

// ScreenUI: position in the screen's view space and whether the vertex belongs to a screen element.
out vec3 screenuiView;
flat out int screenuiLit;

// ScreenUI: items and mobs on the screen are lit from the viewer's side, as in the inventory - an icon facing the
// screen is at full brightness, a block keeps a lighter top and darker sides. World lights shine from above and the
// vertex normals here are not in the screen's view space, so a screen element is left unlit here and lit in the
// fragment shader by its surface normal there (see screenui_light).
#if defined(PER_FACE_LIGHTING) || !defined(NO_CARDINAL_LIGHTING)
bool screenui_on_screen() {
    return UV2 == ivec2(240, 224) || UV2 == ivec2(240, 208);
}

vec4 screenui_mix_light(vec4 color) {
    if (screenui_on_screen()) {
        return color;
    }
    return minecraft_mix_light(Light0_Direction, Light1_Direction, Normal, color);
}
#endif

void main() {
    gl_Position = screenui_fov(ProjMat * ModelViewMat * vec4(Position, 1.0));
    screenuiLit = UV2 == ivec2(240, 224) || UV2 == ivec2(240, 208) ? 1 : 0;
    screenuiView = UV2 == ivec2(240, 208) ? vec3(-Position.x, Position.y, -Position.z)
            : (ModelViewMat * vec4(Position, 1.0)).xyz;

    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);

#ifdef PER_FACE_LIGHTING
    if (screenui_on_screen()) {
        vertexPerFaceColorBack = screenui_mix_light(Color);
        vertexPerFaceColorFront = vertexPerFaceColorBack;
    } else {
        vec2 light = minecraft_compute_light(Light0_Direction, Light1_Direction, Normal);
        vertexPerFaceColorBack = minecraft_mix_light_separate(-light, Color);
        vertexPerFaceColorFront = minecraft_mix_light_separate(light, Color);
    }
#elif defined(NO_CARDINAL_LIGHTING)
    vertexColor = Color;
#else
    vertexColor = screenui_mix_light(Color);
#endif

#ifndef EMISSIVE
    lightMapColor = sample_lightmap(Sampler2, UV2);
#endif

#ifndef NO_OVERLAY
    overlayColor = texelFetch(Sampler1, UV1, 0);
#endif

    texCoord0 = UV0;

#ifdef APPLY_TEXTURE_MATRIX
    texCoord0 = (TextureMat * vec4(UV0, 0.0, 1.0)).xy;
#endif
}
