shader_type spatial;
render_mode cull_disabled;
uniform sampler2D robe_texture : source_color, filter_linear_mipmap;
uniform vec4 robe_color : source_color = vec4(0.18, 0.5, 0.3, 1.0);
void fragment() {
    vec3 base = texture(robe_texture, UV2).rgb;
    float mask = smoothstep(0.005, 0.045, base.g - max(base.r, base.b));
    float detail = clamp(dot(base, vec3(0.2126, 0.7152, 0.0722)) / 0.25, 0.15, 1.8);
    ALBEDO = mix(base, robe_color.rgb * detail, mask);
    ROUGHNESS = 1.0;
}
