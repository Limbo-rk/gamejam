shader_type spatial;
render_mode cull_disabled;

uniform sampler2D neutral_face : source_color, filter_nearest_mipmap;
uniform sampler2D angry_face : source_color, filter_nearest_mipmap;
uniform vec4 skin_color : source_color = vec4(0.76, 0.55, 0.4, 1.0);
uniform bool shooting = false;

void fragment() {
    vec4 face = shooting ? texture(angry_face, UV) : texture(neutral_face, UV);
    // Texture alpha reveals the character's skin, not the space behind the mesh.
    ALBEDO = mix(skin_color.rgb, face.rgb, face.a);
    ROUGHNESS = 1.0;
}
