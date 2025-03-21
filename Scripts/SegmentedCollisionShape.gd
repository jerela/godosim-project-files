extends Node3D

var collision_shapes = []

func _ready() -> void:
	create_collision_shapes_for_segments()

func set_collision_enabled(setting: bool) -> void:
	for cs in collision_shapes:
		cs.set_disabled(!setting)

# creates a physics-compatible collision shape for each segment of a skeleton's body
func create_collision_shapes_for_segments() -> void:
	# get skeleton and skin mesh	
	var skeleton = get_parent().get_node("Armature/Skeleton3D")
	var skin_mesh = skeleton.get_child(0)
	
	# populate an array of segment names with names of the bones in the skeleton, if those bones are suffixed "_segment" (these are the bones that are used during automated skinning in Blender)
	var segment_names = []
	for i in skeleton.get_bone_count():
		var bone_name = skeleton.get_bone_name(i)
		if bone_name.ends_with('_segment'):
			segment_names.append(bone_name)
	
	# get a dictionary where keys are bone names (e.g., "femur_r_segment") and values are arrays of vertices, whose highest-weighted bone is the key
	var vertices_per_bone = get_vertices_for_bones(skin_mesh,segment_names)
	
	# loop through keys in the dictionary and for each bony segment, create a bone attachment to follow the bone, give it a child that is a static body and assign a collision shape for that static body according to the vertices	
	for bone in vertices_per_bone.keys():
		
		# get vertices for the current bone; if there are none, there's no point trying to make a 3D shape; otherwise, create a shape from them
		var vertices = vertices_per_bone[bone]
		if len(vertices) == 0:
			continue
		var shape = ConvexPolygonShape3D.new()
		shape.set_points(vertices)
		
		# assign the newly created shape to a collisionshape
		var collision_shape = CollisionShape3D.new()
		collision_shapes.append(collision_shape)
		collision_shape.set_shape(shape)
		# disable until explicitly enabled
		collision_shape.set_disabled(true)
		
		# create a static body and assign the collision shape as its child to finalize collision detection
		var static_body = StaticBody3D.new()
		static_body.add_child(collision_shape)
		
		# create a bone attachment to follow the movement of the bone in the skeleton; it is assigned to follow the segmentless bone (e.g., for "femur_l_segment" we assign the bone attachment to "femur_l"), which receives OpenSim-calculated transforms elsewhere
		var bone_attachment = BoneAttachment3D.new()
		var segmentless_bone_name = bone.trim_suffix('_segment')
		bone_attachment.set_bone_name(segmentless_bone_name)
		bone_attachment.set_bone_idx(skeleton.find_bone(segmentless_bone_name))
		# we get the transform of the bone to follow and apply its inverse to the static body to "return" the collider where it should be	
		var transf = skeleton.get_bone_global_pose(skeleton.find_bone(segmentless_bone_name))
		static_body.set_global_transform(transf.inverse())
		
		# finally, we add the static body to the bone attachment and add the bone attachment to the skeleton
		bone_attachment.add_child(static_body)
		#bone_attachment.set_global_transform(skeleton.get_bone_global_pose(skeleton.find_bone(segmentless_bone_name)))
		
		skeleton.add_child(bone_attachment)


# get a dictionary containing the vertices for each segment
func get_vertices_for_bones(mesh_instance : MeshInstance3D, bone_names: Array) -> Dictionary:
	
	# we get the parent of the skin mesh, which is the skeleton; required for calculating posed bone transforms
	var skeleton_of_mesh: Skeleton3D = mesh_instance.get_node_or_null(mesh_instance.skeleton)
	
	# create an empty dictionary to hold the vertices for eac bone
	var vertices_per_bone = {}
	for bone_name in bone_names:
		vertices_per_bone[bone_name] = PackedVector3Array()
	

	# if we found skeleton and skin, we calculate the pose-transformed (deformed) position of the vertex
	if(skeleton_of_mesh and mesh_instance.skin):
	
		# iterate through the number of surfaces (so far this has been 1)
		for surface in mesh_instance.mesh.get_surface_count():
			# get arrays at index surface (around 44k vertices, exact number depends on morphology)
			var data := mesh_instance.mesh.surface_get_arrays(surface)
			# get vertices from those arrays
			var vertices: Array = data[Mesh.ARRAY_VERTEX]
			# also get bones
			var bones: Array = data[Mesh.ARRAY_BONES]
			# weights describing how much the vertex follows each bone
			var weights: Array = data[Mesh.ARRAY_WEIGHTS]
			# because each vertex has a number of weights equalling the number of bones, the number of bones is the number of total weights divided by the number of total vertices
			var bone_count := len(weights)/len(vertices)
			
			
			# integrate through the number of vertices in that surface
			for vert_idx in range(len(vertices)):
				var vert = vertices[vert_idx]
		
				var transformed_vert = Vector3.ZERO
				# iterate through the number of bones in the skeleton and calculate the bone-transformed vertex
				for b in bone_count:
					var weight = weights[vert_idx * bone_count + b]
					
					# if there is no weight, the current vertex isn't affected by that bone and we can carry on to the next bone
					if(!weight):
						continue
					
					# calculated the transform of the bone and change the position of the vertex accordingly
					var bone_idx = bones[vert_idx * bone_count + b]
					var bind_pose = mesh_instance.skin.get_bind_pose(bone_idx)
					var bone_global_pose = skeleton_of_mesh.get_bone_global_pose(bone_idx)
					transformed_vert += (bone_global_pose * bind_pose * vert) * weight
				
				# assign the transformed vertex to vert
				vert = transformed_vert
				
				vert = mesh_instance.global_transform * vert
		
		
				var most_important_bone_idx = get_most_important_bone(bone_count, bones, weights, vert_idx)
				if most_important_bone_idx == -1:
					continue
				else:
					var bone_name = skeleton_of_mesh.get_bone_name(most_important_bone_idx)
					vertices_per_bone[bone_name].append(vert)
				
	return vertices_per_bone

# returns the index of the bone that has the highest weight for the given vertex (given by index)
func get_most_important_bone(bone_count: int, bones: Array, weights: Array, vert_idx: int) -> int:
	var max_weight = 0.0
	var idx_max = -1
	
	for b in bone_count:
		var weight_current = weights[vert_idx * bone_count + b]
		var bone_idx = bones[vert_idx * bone_count + b]
		if weight_current > max_weight:
			max_weight = weight_current
			idx_max = bone_idx

	return idx_max
