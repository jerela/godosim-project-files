shader_type spatial;

uniform vec3 colors : source_color;
uniform sampler2D heightmap;
uniform sampler2D albedo;
uniform sampler2D normal;
uniform sampler2D orm;
uniform sampler2D specular;
uniform sampler2D displacement;
uniform sampler2D diffuse;



uniform float uv_tex_scale = 1.0;
uniform float uv_vertex_scale = 1.0;
uniform float height_max;
uniform float height_min;

void vertex() {
	// Called for every vertex the material is visible on.
	VERTEX.y = height_min + texture(heightmap,vec2(UV*uv_vertex_scale)).r*height_max;
}

void fragment() {
	ALBEDO = texture(albedo,UV*uv_tex_scale).rgb;
	ALBEDO = ALBEDO*colors;
	NORMAL = texture(normal,UV*uv_tex_scale).rgb;
	AO = texture(orm,UV*uv_tex_scale).r;
	//ROUGHNESS = texture(orm,UV*uv_scale).g;
	//ROUGHNESS = texture(roughness,UV*uv_tex_scale).r;
	ROUGHNESS = texture(orm,UV*uv_tex_scale).g;
	
	METALLIC = texture(orm,UV*uv_tex_scale).b;
	//SPECULAR = texture(specular,UV*uv_scale).r;
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
