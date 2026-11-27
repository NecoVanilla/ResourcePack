#version 150

#moj_import <minecraft:light.glsl>
#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:projection.glsl>

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV1;
in ivec2 UV2;
in vec3 Normal;

uniform sampler2D Sampler1;
uniform sampler2D Sampler2;

out float sphericalVertexDistance;
out float cylindricalVertexDistance;
out vec4 vertexColor;
out vec4 lightMapColor;
out vec4 overlayColor;
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

void main() {
    gl_Position = screenui_fov(ProjMat * ModelViewMat * vec4(Position, 1.0));

    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);
#ifdef NO_CARDINAL_LIGHTING
    vertexColor = Color;
#else
    vertexColor = minecraft_mix_light(Light0_Direction, Light1_Direction, Normal, Color);
#endif
#ifndef EMISSIVE
    lightMapColor = texelFetch(Sampler2, UV2 / 16, 0);
#endif
    overlayColor = texelFetch(Sampler1, UV1, 0);

    texCoord0 = UV0;
#ifdef APPLY_TEXTURE_MATRIX
    texCoord0 = (TextureMat * vec4(UV0, 0.0, 1.0)).xy;
#endif
}
