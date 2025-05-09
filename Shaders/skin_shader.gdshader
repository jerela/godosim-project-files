
shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D clothing_albedo : source_color,filter_linear_mipmap,repeat_enable;
uniform float point_size : hint_range(0,128);
uniform float roughness : hint_range(0,1);
uniform sampler2D texture_metallic : hint_default_white,filter_linear_mipmap,repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_r,filter_linear_mipmap,repeat_enable;
uniform float specular;
uniform float metallic;
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

// whether we run the shader in segment mask mode (only show the segment whose vertices are connected to a given bone of the skeleton, and hide other vertices)
uniform bool segment_mask_enabled = false;
// index of the bone whose connecting vertices we want to keep visible
uniform uint bone_idx = 0;
// tracks if the current vertex is connected to the bone
varying float mark;

void vertex() {
	if (segment_mask_enabled){
		// mark 0.0 indicates that the vertex is not connected to the target bone
		mark = 0.0;
		// BONE_INDICES contains the indices of up to 4 bones that the vertex is connected to
		// if bone_idx is any of those four, mark becomes 1.0 (or BONE_WEIGHTS.i); otherwise it remains at 0.0
		mark = max((BONE_INDICES.x == bone_idx) ? BONE_WEIGHTS.x : 0.0, mark);
		mark = max((BONE_INDICES.y == bone_idx) ? BONE_WEIGHTS.y : 0.0, mark);
		mark = max((BONE_INDICES.z == bone_idx) ? BONE_WEIGHTS.z : 0.0, mark);
		mark = max((BONE_INDICES.w == bone_idx) ? BONE_WEIGHTS.w : 0.0, mark);
		// round if required; useful if creating a binary mask
		mark = round(mark);
	} else {
		UV=UV*uv1_scale.xy+uv1_offset.xy;
	}

}

void fragment() {
	// using alpha scissor mode is necessary to prevent the material from going into alpha blend pipeline, which causes strange transparency sorting issues and prevents casting shadows
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (segment_mask_enabled){
		// sets the non-target segments to transparent (alpha=0.0) and the target segment to opaque (alpha=1.0)
		ALPHA = mark;
	} else {
		ALPHA = 1.0;
		vec2 base_uv = UV;
		vec4 albedo_tex = texture(texture_albedo,base_uv);
		vec4 clothes_tex = texture(clothing_albedo,base_uv);
		ALBEDO = albedo.rgb * albedo_tex.rgb;
		if (clothes_tex.a == 1.0){
			ALBEDO = clothes_tex.rgb;
		};
		float metallic_tex = dot(texture(texture_metallic,base_uv),metallic_texture_channel);
		METALLIC = metallic_tex * metallic;
		vec4 roughness_texture_channel = vec4(1.0,0.0,0.0,0.0);
		float roughness_tex = dot(texture(texture_roughness,base_uv),roughness_texture_channel);
		ROUGHNESS = roughness_tex * roughness;
		SPECULAR = specular;
	}

}
