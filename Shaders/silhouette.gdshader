shader_type spatial;
// set render mode to unshaded so the silhouette doesn't interact with light
render_mode unshaded;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// paint the silhouette white so it stands out against the black background
	ALBEDO = vec3(1.0,1.0,1.0);
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
