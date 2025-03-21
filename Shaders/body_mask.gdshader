shader_type spatial;
// we don't want the visible part of the mask interacting with light, so we use unshaded mode
render_mode unshaded;
// tracks whether weights connect the current vertex to the bone
varying float mark;
// index of the bone in the skeleton whose connecting vertices we keep visible, while hiding others
uniform uint bone_idx = 0;

void vertex() {
	// mark 0.0 indicates that the vertex is not connected to the target bone
	mark = 0.0;
	// BONE_INDICES contains the indices of up to 4 bones that the vertex is connected to
	// if bone_idx is any of those four, mark becomes 1.0 (or BONE_WEIGHTS.i); otherwise it remains at 0.0
	mark = max((BONE_INDICES.y == bone_idx) ? BONE_WEIGHTS.y : 0.0, mark);
	mark = max((BONE_INDICES.x == bone_idx) ? BONE_WEIGHTS.x : 0.0, mark);
	mark = max((BONE_INDICES.z == bone_idx) ? BONE_WEIGHTS.z : 0.0, mark);
	mark = max((BONE_INDICES.w == bone_idx) ? BONE_WEIGHTS.w : 0.0, mark);
	// round if required; useful if creating a binary mask
	mark = round(mark);
}

void fragment() {
	// sets the non-target limbs to transparent and highlight the target limb with white color
	ALPHA = mark;
	ALBEDO.r = mark;
	ALBEDO.g = mark;
	ALBEDO.b = mark;
}
