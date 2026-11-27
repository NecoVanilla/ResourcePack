#version 330

#ifndef IS_SEE_THROUGH
#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:sample_lightmap.glsl>
#endif

#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:projection.glsl>

in vec3 Position;
in vec4 Color;
#ifndef IS_SEE_THROUGH
in ivec2 UV2;
uniform sampler2D Sampler2;
out float sphericalVertexDistance;
out float cylindricalVertexDistance;
#endif

out vec4 vertexColor;

// ScreenUI pack-cursor: the cursor is marked by its background color - R 1, G = its colour slot (254 fill,
// 253 outline, 247-252 the cursor palette, see UiSession.CursorColor), B = cursor x range * 64,
// A = 127 + sensitivity / 0.0005 - and follows the head rotation every frame.
bool screenui_byte(float c, float b) {
    return abs(c * 255.0 - b) < 0.5;
}

bool screenui_cursor() {
    float g = Color.g * 255.0;
    return screenui_byte(Color.r, 1.0) && g > 246.5 && g < 254.5;
}

// The cursor palette - the same colours as UiSession.CursorColor.
vec3 screenui_palette(int slot) {
    if (slot == 254) return vec3(255.0, 255.0, 255.0) / 255.0;
    if (slot == 253) return vec3(12.0, 12.0, 16.0) / 255.0;
    if (slot == 252) return vec3(138.0, 90.0, 43.0) / 255.0;
    if (slot == 251) return vec3(90.0, 58.0, 26.0) / 255.0;
    if (slot == 250) return vec3(111.0, 230.0, 207.0) / 255.0;
    if (slot == 249) return vec3(42.0, 157.0, 138.0) / 255.0;
    if (slot == 248) return vec3(201.0, 255.0, 244.0) / 255.0;
    return vec3(252.0, 212.0, 58.0) / 255.0;
}

vec4 screenui_recolor(vec4 lit) {
    if (!screenui_cursor()) {
        return lit;
    }
    return vec4(screenui_palette(int(Color.g * 255.0 + 0.5)) * lit.g / Color.g, 1.0);
}

// ScreenUI: the screen is drawn as if the client's FOV were 70, whatever the setting.
// Screen displays have light block 15 / sky 14 (UV2 = 240, 224) and sit 0.5-2 blocks in front of the camera.
// pack-cursor: light block 15 / sky 13 (UV2 = 240, 208) - the player looks at the screen with their own eyes and
// turns their head freely. The screen (0.3-3 blocks south of the camera) is drawn from a fixed camera that faces
// south at FOV 70, whatever the head rotation; its 16:9 area always fits the window (a narrower one shrinks it).
vec4 screenui_fov(vec4 clip) {
#ifndef IS_SEE_THROUGH
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
            if (screenui_cursor()) {
                vec4 mark = Color * 255.0;
                float sensitivity = (mark.a - 127.0) * 0.0005;
                float range = mark.b / 64.0;
                float yaw = degrees(atan(-ModelViewMat[2][0], -ModelViewMat[0][0]));
                float pitch = degrees(asin(clamp(ModelViewMat[1][2], -1.0, 1.0)));
                // F5 front view: the camera looks back at the player, its rotation is the opposite of the head's.
                // The server keeps the head within 85 deg of the screen, so a camera past 90 deg is the front view.
                if (abs(yaw) > 90.0) {
                    yaw = yaw > 0.0 ? yaw - 180.0 : yaw + 180.0;
                    pitch = -pitch;
                }
                vec2 at = clamp(vec2(yaw, -pitch) * sensitivity, vec2(-range, -1.1), vec2(range, 1.1));
                clip.xy += vec2(at.x / aspect, at.y) * fit / 1.1 * clip.w;
                // The cursor sits in the screen plane (UiSession.CURSOR_Z) but takes its depth 0.7 closer: over
                // dialogs and 3D models, yet without parallax against the buttons when the camera is slightly off.
                float near = v.z + 0.7;
                clip.z = (ProjMat[2][2] * near + ProjMat[3][2]) / (ProjMat[2][3] * near) * clip.w;
            }
        }
    }
#endif
    return clip;
}

void main() {
    gl_Position = screenui_fov(ProjMat * ModelViewMat * vec4(Position, 1.0));

#ifndef IS_SEE_THROUGH
    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);
    vertexColor = Color * sample_lightmap(Sampler2, UV2);
#else
    vertexColor = Color;
#endif
    vertexColor = screenui_recolor(vertexColor);
}
