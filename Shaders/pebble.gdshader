
shader_type spatial;
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color,filter_linear_mipmap,repeat_enable;

uniform float vert_x_factor = 1.0;
uniform float vert_y_factor = 1.0;
uniform float vert_z_factor = 1.0;

void vertex() {
	VERTEX.x *= vert_x_factor;
	VERTEX.y *= vert_y_factor;
	VERTEX.z *= vert_z_factor;
}






void fragment() {
	vec2 base_uv = UV;
	vec4 albedo_tex = texture(texture_albedo,base_uv);
	ALBEDO = albedo.rgb * albedo_tex.rgb;
}
