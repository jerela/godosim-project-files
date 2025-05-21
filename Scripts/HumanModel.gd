# Handles the skin mesh of the visual avatar, including setting its poses and OpenSim integration.

extends Node3D

@export var node_gui : Node
@export var node_player : Node
@export var node_camera : Node
@export var output : Node

# controls whether we (re)run tracker whenever sex and weight of the avatar are changed, or use the pre-calculated simulation (if any exists); set by the config file, so the value initialized here is just a placeholder
var persistent_msk_data = false

# stores data from already run simulations if persistent MSK data is on
var skeleton_tracker_container: Dictionary = {}

# tracks if simulation has been run at least once
var simulation_successful: bool = false

# tracks if the visual human avatar (skin mesh) has been selected by the user at least once
var mesh_changed: bool = false

# whether pose has changed since we last calculated the 3D bounding box of the skin mesh; if true, we should recalculate it; if false, we do not need to recalculate it when generating image
var recalculate_bounding_box: bool = true
var bounding_box: AABB

var total_time: float = 0.0

var loop_motion: bool = false

var dt

var current_frame: int = 0

@onready var skin_material = preload("res://Materials/skin_material.tres")

@onready var overlay_node = load("res://Scenes/OverlayCircle.tscn")

# whether the visualization of motion is currently running
var enabled: bool = false

# whether to show the origins of bodies as overlaid circles in the viewport
var overlay_enabled: bool = false

@onready var godosim = Godosim.new()
#@onready var utils = GDOSUtils.new() # uncomment if you want to calculate AABB (bounding box) using a C++ module instead of using a GDScript function

@onready var rigid_skeleton = $bones_meshes_up/Armature/Skeleton3D
@onready var skeleton = null
@onready var skin_mesh = null

@onready var segmented_collision_shape = load('res://Scenes/SegmentedCollisionShape.tscn')

var shader_material_paths = {
	"none": "res://Materials/blank_material.tres",
	"silhouette": "res://Materials/silhouette_material.tres",
	"body_mask": "res://Materials/body_mask_material.tres"
}

# default sex and weight for the visual avatar
var sex: String = 'male'
var weight: String = 'zero'

var skin_male_textures: Dictionary = {}
var skin_female_textures: Dictionary = {}
var clothing_textures: Dictionary = {}

# whether we have initialized the variables for saving annotations to file
var annotations_initialized: bool = false



# generalized coordinate names are populated later in run_simulation()
var generalized_coordinate_names: Array = []
var generalized_coordinate_values = {}

# string-type names of bodies whose transforms will be described and assigned to the virtual avatar; this will be populated later in a function
var tracked_bodies: Array = []

# stores string names of virtual markers in the MSK model
var marker_names: Array = []
# stores 3D positions of virtual markers, keyed by the name of the marker
var marker_positions: Dictionary = {}

# store body rotations and positions
@onready var rotations: Dictionary = {}
@onready var positions: Dictionary = {}

# store joint translations
@onready var joint_translations = {}

# stores names of joints that will be tracked; populated automatically when running simulation
var joint_names = []

# after populating, maps the names of tracked OpenSim bodies to their bone indices in the armature of the skeleton
var bone_name_to_idx: Dictionary = {}

# dict to hold viweport-overlaid circles representing the positions of bodies
var overlay_circles: Dictionary = {}

# dict from the name of the joint to the name of its parent body
var joint_to_parent: Dictionary = {}

var shader_materials: Dictionary = {}

# will be populated with paths when reading the configuration file
var cfg_paths: Dictionary = {}

# tracks whether the program is in demonstration mode or not; set in _ready()
var demo_mode: bool = false

# step parameter for bounding box calculation to skip some of the vertices of the skin mesh, greatly speeding up computation but possibly causing inaccuracy in the bounding box creation
var bb_step: int = 1
# padding to add to all four sides of the 2D bounding box
var bb_padding: int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var skin_male_paths = {}
	var skin_female_paths = {}
	var clothing_paths = {}
	
	# if the parent of the HumanModel node is "Demo" node, we are in demonstation mode and set the according variable
	if get_parent().get_name() == "Demo":
		print("Program launching in demonstration mode.")
		demo_mode = true
	else:
		demo_mode = false
	
	
	read_config('config.cfg')
	import_human_meshes(cfg_paths['path_ext_human_mesh'])
	populate_skin_texture_dictionary(cfg_paths['path_ext_tex_skin_male'], skin_male_paths)
	populate_skin_texture_dictionary(cfg_paths['path_ext_tex_skin_female'], skin_female_paths)
	populate_clothing_texture_dictionary(cfg_paths['path_ext_tex_clothing'], clothing_paths)
	create_skin_textures(skin_male_paths, skin_female_paths)
	create_clothing_textures(clothing_paths)
	prepare_shader_materials()
	set_skin_texture("none")
	set_clothing_texture("none")

	
func _physics_process(delta: float) -> void:
	# if motion visualization is enabled, update it
	if enabled:
		update_visualization(delta, 0.25)
	
	# if esc is pressed, close program
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()
		
func read_config(cfg_name):
	# initialize an object to read configuration files
	var config = ConfigFile.new()
	var err = config.load(str("user://Config/", cfg_name))
	if err != OK:
		print('config reading failed')
		return
	persistent_msk_data = config.get_value('skeletontracker', 'persistent_musculoskeletal_simulation_data')
	cfg_paths['path_ext_tex_skin_male'] = config.get_value('external_data', 'path_textures_skin_male')
	cfg_paths['path_ext_tex_skin_female'] = config.get_value('external_data', 'path_textures_skin_female')
	cfg_paths['path_ext_tex_clothing'] = config.get_value('external_data', 'path_textures_clothing')
	cfg_paths['path_ext_human_mesh'] = config.get_value('external_data', 'path_human_mesh')
	
	bb_step = config.get_value('bounding_box', 'step')
	bb_padding = config.get_value('bounding_box', 'padding')
	
	
	var resolution = config.get_value('project_settings', 'screen_resolution')
	get_viewport().set_size(resolution)

# import meshes of human skins from an external directory
func import_human_meshes(path: String) -> void:
	# get names of files in the given path
	var files = DirAccess.get_files_at(path)
	# loop through files (assumedly GLB files)
	for file_name in files:
		# for importing a GLB/GLTF as a scene, we instantiate two new objects to hold their data
		var gltf_document_load = GLTFDocument.new()
		var gltf_state_load = GLTFState.new()
		# make sure we succeeded
		var error = gltf_document_load.append_from_file(str(path.path_join(file_name)), gltf_state_load)
		if error == OK:
			# import the mesh file as a root scene with children
			var gltf_scene_root_node = gltf_document_load.generate_scene(gltf_state_load)
			# add a segmented collision shape as its child to generate segment-specific collision shapes
			gltf_scene_root_node.add_child(segmented_collision_shape.instantiate())
			# add the imported scene to this scene as a child
			$HumanMeshes.add_child(gltf_scene_root_node)
			# hide the mesh by default
			gltf_scene_root_node.visible = false
		else:
			printerr("Couldn't load glTF scene (error code: %s)." % error_string(error))
			get_tree().quit()

# populate the dictionaries mapping skin albedo names to their file paths
func populate_skin_texture_dictionary(path: String, target_dictionary: Dictionary) -> void:
	var skins = DirAccess.get_files_at(path)
	for file_name in skins:
		if file_name == 'skin_albedo_gray.png':
			target_dictionary['none'] = str(path.path_join(file_name))
		else:
			# first, we remove "skin_m_" or "skin_f_" from the beginning of the name
			var key = file_name.right(-7)
			# second, remove "_ALB.png" from the end of the name
			key = key.rstrip('_ALB.png')
			# now we have the key, e.g., "african_01", and we can populate dictionaries
			target_dictionary[key] = str(path.path_join(file_name))
	return

func populate_clothing_texture_dictionary(path: String, target_dictionary: Dictionary) -> void:
	var textures = DirAccess.get_files_at(path)
	for file_name in textures:
		if file_name == 'skin_empty.png':
			target_dictionary['none'] = str(path.path_join(file_name))
		else:
			# first, we remove "rp_" from the beginning of the name
			var key = file_name.lstrip('rp_')
			key = key.rstrip('.png')
			# now we have the key, e.g., "aaron_posed_002_texture_10", and we can populate dictionaries
			target_dictionary[key] = str(path.path_join(file_name))
	return
		
# returns the length of the pelvis position vector, which should equal the number of frames
func get_num_frames() -> int:
	return len(godosim.get_position_vectors('pelvis'))

# returns the number of male or female skin textures depending on which sex is currently chosen
func get_num_skin_textures() -> int:
	if sex == 'male':
		return len(skin_male_textures)
	elif sex == 'female':
		return len(skin_female_textures)
	else:
		printerr('ERROR! Sex not chosen.')
		get_tree().quit()
		return 0

# returns the number of clothing textures
func get_num_clothing_textures() -> int:
	return len(clothing_textures)

func prepare_shader_materials() -> void:
	var keys = shader_material_paths.keys()
	for key in keys:
		var new_material = load(shader_material_paths[key])
		shader_materials[key] = new_material
		
	skin_material.set_next_pass(shader_materials.values()[0])

func switch_shader_effect(direction: int) -> String:
	var materials
	var keys
	materials = shader_materials.values()
	keys = shader_materials.keys()
	var current_material = skin_material.get_next_pass()
	var idx = materials.find(current_material)
	var new_idx = idx + direction
	if new_idx < 0:
		new_idx += materials.size()
	elif new_idx > materials.size()-1:
		new_idx -= materials.size()
	skin_material.set_next_pass(materials[new_idx])
	
	var current_material_key = keys[new_idx]
	return current_material_key

# change skin mesh according to indices of sex (male=0, female=1) and weights (plus2=0, zero=1, minus2=2); calls change_mesh()
# this function is only used by the demo; don't call this function from Generate
func change_mesh_by_index(sex_idx: int, weight_idx: int) -> Array:
	
	if !demo_mode:
		printerr("ERROR: HumanModel::change_mesh_by_index() was called even though program is not in demo mode! Exiting.")
		get_tree().quit()
	
	var sex_str = ''
	var weight_str = ''
	
	if sex_idx == 0:
		sex_str = 'male'
	elif sex_idx == 1:
		sex_str = 'female'
		
	if weight_idx == 0:
		weight_str = 'plus2'
	elif weight_idx == 1:
		weight_str = 'zero'
	elif weight_idx == 2:
		weight_str = 'minus2'
	
	return change_mesh(sex_str,weight_str)

# when the sex or weight of the human to visualize is changed, change the mesh accordingly
func change_mesh(sex_str: String, weight_str: String) -> Array:
	
	# indicate that the user has selected at least some weight and sex for the visual avatar
	mesh_changed = true
	
	# first, define if we should use female or male textures and their names (keys)
	var keys
	var textures
	if sex == 'male':
		textures = skin_male_textures.values()
		keys = skin_male_textures.keys()
	elif sex == 'female':
		textures = skin_female_textures.values()
		keys = skin_female_textures.keys()
		
	var textures_clothing = clothing_textures.values()
	var keys_clothing = clothing_textures.keys()
	# we store the current texture to make sure we keep the texture despite changing sex or weight
	var current_texture = skin_material.get_shader_parameter("texture_albedo")
	var current_texture_clothing = skin_material.get_shader_parameter("clothing_albedo")
	var idx = textures.find(current_texture)
	var idx_clothing = textures_clothing.find(current_texture_clothing)
	var current_texture_key = keys[idx]
	var current_texture_key_clothing = keys_clothing[idx_clothing]

	# set variables of this class according to the input parameters of the function
	sex = sex_str
	weight = weight_str
	
	# get the right meshes by node path
	skeleton = get_node('HumanMeshes/human_' + sex + '_' + weight + '/Armature/Skeleton3D')
	skin_mesh = get_node('HumanMeshes/human_' + sex + '_' + weight + '/Armature/Skeleton3D/skin_mesh_' + sex + '_' + weight)
	
	# hide all existing meshes and disable their collision shapes by default
	for node in $HumanMeshes.get_children():
		node.visible = false
		# disable all collision shapes for visual models that have them
		if node.get_node_or_null("SegmentedCollisionShape"):
			node.get_node("SegmentedCollisionShape").set_collision_enabled(false)
	
	# then enable CollisionShape3D for the current skeleton
	skeleton.get_parent().get_parent().get_node("SegmentedCollisionShape").set_collision_enabled(true)
	# and then make only the current mesh visible
	get_node('HumanMeshes/human_' + sex + '_' + weight).visible = true
	
	
	
	# on the new mesh, set the same texture as we had on the previous mesh
	set_skin_texture(current_texture_key)
	set_clothing_texture(current_texture_key_clothing)
	
	# if dt is null, then we haven't run the OpenSim simulation yet; if we have, then we switch frame with 0 offset (i.e., we set the mesh deform to same motion as before)
	if dt != null:
		switch_frame(0)
		
	populate_tracked_body_indices()
		
	# return the name of the current texture to update the GUI (not necessary if the texture doesn't change?)
	return [current_texture_key, current_texture_key_clothing]

# set the bodies in the OpenSim model whose motion is fetched
func set_tracked_bodies(in_bodies: PackedStringArray) -> void:
	tracked_bodies = in_bodies
	godosim.set_tracked_bodies(tracked_bodies)
	print("Tracked bodies set to:", var_to_str(tracked_bodies))

# function to automatically find the joints whose parent body is defined as a tracked body; we can only track joints whose parent bodies we track, because we need the parent body's 3D transforms to calculate the joint's 3D transform
func assign_valid_joint_names():
	joint_names.clear()
	var all_joint_names = godosim.get_joint_names()
	for joint in all_joint_names:
		var parent_body_name = godosim.get_parent_body_name(joint)
		if parent_body_name in tracked_bodies:
			joint_names.append(joint)

# loads images of different textures and prepares them to be assigned to materials; run only once
func create_skin_textures(skin_male_paths: Dictionary, skin_female_paths: Dictionary) -> void:
	for key in skin_male_paths.keys():
		var tex_img = Image.load_from_file(skin_male_paths[key])
		var tex = ImageTexture.create_from_image(tex_img)
		skin_male_textures[key] = tex
	for key in skin_female_paths.keys():
		var tex_img = Image.load_from_file(skin_female_paths[key])
		var tex = ImageTexture.create_from_image(tex_img)
		skin_female_textures[key] = tex
	print('Loaded ', skin_male_textures.size(), ' male skin textures and ', skin_female_textures.size(), ' female skin textures.')
	
	# make sure all meshes have a surface override material that is skin_material
	for mesh in $HumanMeshes.get_children():
		skin_mesh = mesh.get_node('Armature/Skeleton3D').get_child(0)
		skin_mesh.set_surface_override_material(0, skin_material)
		# ensure that the skin mesh is also visible on layer 2, which the mask-viewing Camera3D node uses
		skin_mesh.set_layer_mask_value(2,true)

func create_clothing_textures(clothing_paths: Dictionary) -> void:
	for key in clothing_paths.keys():
		var tex_img = Image.load_from_file(clothing_paths[key])
		var tex = ImageTexture.create_from_image(tex_img)
		clothing_textures[key] = tex
	print('Loaded ', clothing_textures.size(), ' clothing textures.')
	
# populate the bone_name_to_idx dictionary
func populate_tracked_body_indices() -> void:
	for body in tracked_bodies:
		for i in range(skeleton.get_bone_count()):
			var current_name = skeleton.get_bone_name(i)
			# we have to look for body/bone names with the suffix "_segment" because those are automatically skinned to deform the mesh, i.e., they have weights (see the Blender pipeline)
			if str(body, "_segment") == current_name:
				bone_name_to_idx[body] = i

# enable or disable segment mask (showing only specific segments as silhouettes instead of full body normally) in the main material shader of the mesh	
func set_segment_mask_enabled(mode: bool) -> void:
	skin_material.set_shader_parameter('segment_mask_enabled',mode)

# set the index of the segment to show, provided segment mask is enabled
func set_segment_index(idx: int) -> void:
	skin_material.set_shader_parameter('bone_idx',idx)
	skin_material.get_next_pass().set_shader_parameter("bone_idx",idx)
	
# sets skin texture to desired ethinicity by key
func set_skin_texture(key: String) -> void:
	if sex == 'male':
		if key == 'none':
			skin_material.set_shader_parameter("texture_albedo", skin_male_textures.values()[0])
		else:
			skin_material.set_shader_parameter("texture_albedo",skin_male_textures[key])
	elif sex == 'female':
		if key == 'none':
			skin_material.set_shader_parameter("texture_albedo", skin_female_textures.values()[0])
		else:
			skin_material.set_shader_parameter("texture_albedo",skin_female_textures[key])

func set_clothing_texture(key: String) -> void:
	if key == 'none':
		skin_material.set_shader_parameter("clothing_albedo",clothing_textures.values()[0])
	else:
		skin_material.set_shader_parameter("clothing_albedo",clothing_textures[key])

# allows switching through skin textures on the fly, useful for GUI signals
func switch_skin_texture(direction: int) -> String:
	# find current material index in the values array
	var textures
	var keys
	if sex == 'male':
		textures = skin_male_textures.values()
		keys = skin_male_textures.keys()
	elif sex == 'female':
		textures = skin_female_textures.values()
		keys = skin_female_textures.keys()
	var current_texture = skin_material.get_shader_parameter("texture_albedo")
	var idx = textures.find(current_texture)
	var new_idx = idx + direction
	if new_idx < 0:
		new_idx += textures.size()
	elif new_idx > textures.size()-1:
		new_idx -= textures.size()
	skin_material.set_shader_parameter("texture_albedo", textures[new_idx])
	
	var current_texture_key = keys[new_idx]
	return current_texture_key

# sets the current skin texture according to passed index
func set_skin_texture_by_index(idx: int) -> void:
	if sex == 'male':
		skin_material.set_shader_parameter("texture_albedo", skin_male_textures.values()[idx])
	elif sex == 'female':
		skin_material.set_shader_parameter("texture_albedo", skin_female_textures.values()[idx])

# sets the current clothing texture according to passed index
func set_clothing_texture_by_index(idx: int) -> void:
	skin_material.set_shader_parameter("clothing_albedo", clothing_textures.values()[idx])

# sets the current clothing texture to the previous or next index depending on direction (1 or -1)
func switch_clothing_texture(direction: int) -> String:
	# find current material index in the values array
	var textures
	var keys
	textures = clothing_textures.values()
	keys = clothing_textures.keys()
	var current_texture = skin_material.get_shader_parameter("clothing_albedo")
	var idx = textures.find(current_texture)
	var new_idx = idx + direction
	if new_idx < 0:
		new_idx += textures.size()
	elif new_idx > textures.size()-1:
		new_idx -= textures.size()
	skin_material.set_shader_parameter("clothing_albedo", textures[new_idx])
	
	var current_texture_key = keys[new_idx]
	return current_texture_key



# set the full path to the model file; called by GUI
func set_model(model_path: String) -> void:
	godosim.set_model_file(model_path)
	
# set the full path to the motion file; called by GUI
func set_motion(motion_path: String) -> void:
	godosim.set_motion_file(motion_path)

func update_skeleton_visualization(mode: bool) -> void:
	$bones_meshes_up.visible = mode
	get_node('HumanMeshes/human_' + sex + '_' + weight).visible = !mode
	
# update the visibility of overlay circles according to setting, which may be changed from the GUI
func update_overlay_circles(mode: bool) -> void:
	overlay_enabled = mode
	for circle in overlay_circles.values():
		circle.visible = mode

# return the Vector3 of pelvis body position of the mesh; used in Generate.gd to center the mesh even if pelvis_tx or other translational coordinates are non-zero
func get_current_root_position() -> Vector3:
	return positions['pelvis'][current_frame]

# uses the SkeletonTracker C++ class through Godosim to simulate motions using the musculoskeletal model and fetch corresponding body and joint translations and rotations; called by GUI
func run_simulation() -> bool:
	
	# if this mode is true, we save persistent data so we don't have to rerun tracker anymore; otherwise we always re-run the simulation
	if persistent_msk_data:
	
		# extract the file name part of the full file path of model and motion file (e.g., if the model file is DRIVE/Users/me/Documents/Models/model.osim", only "model.osim" is extracted
		# the logic works by getting the substring after the last slash (/) character in the full file path string
		var model_file_name = godosim.get_model_file()
		var motion_file_name = godosim.get_motion_file()
		var model_id = model_file_name.get_slice('/', model_file_name.get_slice_count('/')-1)
		var motion_id = motion_file_name.get_slice('/', motion_file_name.get_slice_count('/')-1)
		
		if model_file_name == '' or motion_file_name == '':
			print('Cannot run simulation because the model file or the motion file is not specified. Make sure you have pressed the "Set model" and "Set motion" buttons after writing the full file paths.')
			print('Model file: ', model_file_name)
			print('Motion file: ', motion_file_name)
			return false
		
		if godosim.get_tracked_bodies().is_empty():
			print('Cannot run simulation because tracked bodies have not been set. Make sure you have pressed the "Set bodies" button after writing the names of the bodies you want to track in the OpenSim model, separated by commas with no whitespaces between the names.')
			print('Tracked bodies: ', godosim.get_tracked_bodies())
			return false
		
		# we construct a tracker key of the model and motion file names so we don't have to run SkeletonTracker again if we already have for that combination
		var tracker_key = str(model_id, '-', motion_id)

		# if we've run SkeletonTracker for the model-motion combination already, just fetch the data from skeleton_tracker_container
		if skeleton_tracker_container.has(tracker_key):
			print(str('Retrieving previously simulated tracker output for key: ', tracker_key))
			rotations = skeleton_tracker_container[tracker_key]['rotations']
			positions = skeleton_tracker_container[tracker_key]['positions']
			joint_to_parent = skeleton_tracker_container[tracker_key]['joint_to_parent']
			joint_translations = skeleton_tracker_container[tracker_key]['joint_translations']
			marker_positions = skeleton_tracker_container[tracker_key]['marker_positions']
			generalized_coordinate_values = skeleton_tracker_container[tracker_key]['generalized_coordinate_values']
			dt = skeleton_tracker_container[tracker_key]['dt']
		# otherwise, run SkeletonTracker and store the data in skeleton_tracker_container
		else:
			print(str('Running tracker for key: ', tracker_key))
			godosim.run_tracker()
			assign_valid_joint_names()
			
			marker_names = godosim.get_marker_names()
			
			generalized_coordinate_names = godosim.get_coordinate_names()
			
			var generate_overlay_circles = false
			if overlay_circles.is_empty():
				generate_overlay_circles = true
			
			# get the rotations and position (= transform) for each body
			for body in tracked_bodies:
				#rotations[body] = Array(s.get_rotation_quaternions(body))
				# there is a discrepancy between using quaternions and rotation matrices, so we'll use rotation matrices, as those seem to work better here
				rotations[body] = Array(godosim.get_rotation_matrices(body))
				positions[body] = Array(godosim.get_position_vectors(body))

			
			for joint in joint_names:
				joint_to_parent[joint] = godosim.get_parent_body_name(joint)
				joint_translations[joint] = godosim.get_joint_translation_vector(joint)
				if generate_overlay_circles:
					overlay_circles[joint] = overlay_node.instantiate()
					add_child(overlay_circles[joint])
					overlay_circles[joint].visible = false
					
					
			for marker in marker_names:
				marker_positions[marker] = godosim.get_marker_positions(marker)
				if generate_overlay_circles:
					overlay_circles[marker] = overlay_node.instantiate()
					add_child(overlay_circles[marker])
					overlay_circles[marker].visible = false
			
			for gc in generalized_coordinate_names:
				generalized_coordinate_values[gc] = godosim.get_coordinate_values(gc)
			
			dt = godosim.get_time_step()
			
			skeleton_tracker_container[tracker_key] = {}
			skeleton_tracker_container[tracker_key]['rotations'] = rotations.duplicate(true)
			skeleton_tracker_container[tracker_key]['positions'] = positions.duplicate(true)
			skeleton_tracker_container[tracker_key]['joint_to_parent'] = joint_to_parent.duplicate(true)
			skeleton_tracker_container[tracker_key]['joint_translations'] = joint_translations.duplicate(true)
			skeleton_tracker_container[tracker_key]['marker_positions'] = marker_positions.duplicate(true)
			skeleton_tracker_container[tracker_key]['generalized_coordinate_values'] = generalized_coordinate_values.duplicate(true)
			skeleton_tracker_container[tracker_key]['dt'] = godosim.get_time_step()
	# if persistent musculoskeletal data is not true, re-run the simulation even if we already calculated it before
	else:
		godosim.run_tracker()
		assign_valid_joint_names()
		
		marker_names = godosim.get_marker_names()
		
		generalized_coordinate_names = godosim.get_coordinate_names()
			
		var generate_overlay_circles = false
		if overlay_circles.is_empty():
			generate_overlay_circles = true
		
		# get the rotations and position (= transform) for each body
		for body in tracked_bodies:
			#rotations[body] = Array(s.get_rotation_quaternions(body))
			# there is a discrepancy between using quaternions and rotation matrices, so we'll use rotation matrices, as those seem to work better here
			rotations[body] = Array(godosim.get_rotation_matrices(body))
			positions[body] = Array(godosim.get_position_vectors(body))

		
		for joint in joint_names:
			joint_to_parent[joint] = godosim.get_parent_body_name(joint)
			joint_translations[joint] = godosim.get_joint_translation_vector(joint)
			if generate_overlay_circles:
				overlay_circles[joint] = overlay_node.instantiate()
				add_child(overlay_circles[joint])
				overlay_circles[joint].visible = false
		
		for marker in marker_names:
			marker_positions[marker] = godosim.get_marker_positions(marker)
			if generate_overlay_circles:
				overlay_circles[marker] = overlay_node.instantiate()
				add_child(overlay_circles[marker])
				overlay_circles[marker].visible = false
		
		for gc in generalized_coordinate_names:
				generalized_coordinate_values[gc] = godosim.get_coordinate_values(gc)
		
		dt = godosim.get_time_step()

	return true
		
# enables visualization; called by GUI
func play_visualization() -> void:
	enabled = true
	
# disables visualization; called by GUI
func pause_visualization() -> void:
	enabled = false

# define whether the visualized motion loops after reaching the last frame, or stops there
func set_loop_motion(toggle: bool) -> void:
	loop_motion = toggle

# set the visualization to a specific frame
func go_to_frame(frame: int) -> void:
	set_visualization(frame)

# jump a single frame forward or backward in the visualization
func switch_frame(direction: int) -> void:
	update_visualization(direction*dt,1.0)

# update GUI elements with current frame and time
func update_gui(frame: int) -> void:
	var max_frame = len(rotations[tracked_bodies[0]])
	var max_time = max_frame*dt
	node_gui.set_motion_frame(frame+1,max_frame,(frame+1)*dt,max_time)

# set the visualization to a specified frame
func set_visualization(frame: int) -> void:
	visualize_frame(frame)
	total_time = frame*dt
	if node_gui:
		update_gui(frame)

# sets the current frame to whatever we want; note that this doesn't do anything except for updating the value of the current_frame variable, so it's just for "bookkeeping"
func set_current_frame(frame: int) -> void:
	current_frame = frame

func get_current_frame() -> int:
	return current_frame

# set the transform of skeleton bones according to corresponding bodies in the OpenSim model
func visualize_frame(frame: int) -> void:	
	current_frame = frame
	
	# only try to access the skeleton is it isn't null (i.e., it has been assigned properly)
	if skeleton:
		# set the transform for each bone in the armature
		for body in tracked_bodies:
			var current_body_transform = Transform3D(Basis(rotations[body][frame]),Vector3(positions[body][frame]))
			if skeleton.find_bone(body) > -1:
				skeleton.set_bone_global_pose_override(skeleton.find_bone(body), current_body_transform, 1.0, true)
			if rigid_skeleton.find_bone(body) > -1:
				rigid_skeleton.set_bone_global_pose_override(rigid_skeleton.find_bone(body), current_body_transform, 1.0, true)
		
		# if overlay is enabled, set the positions of overlay circles to where joints are (each joint's parent body + the joint's position in the parent body's coordinate system)
		if overlay_enabled:
			for joint in joint_names:
				var joint_position = find_joint_global_position(joint,frame)
				overlay_circles[joint].set_global_position(joint_position)
			for marker in marker_names:
				overlay_circles[marker].set_global_position(marker_positions[marker][frame])
		
		# when next generating images, we must recalculate the 3D bounding box according to the deformation of the pose we just set
		recalculate_bounding_box = true

# progress the visualization from where it was before
func update_visualization(delta: float, speed_factor: float) -> void:
	total_time += delta*speed_factor
	current_frame = find_frame(total_time,dt)
	
	if current_frame >= len(rotations[tracked_bodies[0]]):
		if loop_motion:
			current_frame -= len(rotations[tracked_bodies[0]])
			total_time = 0
		else:
			enabled = false
			return
		
	if node_gui:
		update_gui(current_frame)
		
	visualize_frame(current_frame)
	


# get the global position of a joint given its name and frame in the motion data
func find_joint_global_position(joint_name: String, frame: int) -> Vector3:
	var parent_body_name = joint_to_parent[joint_name]
	# get the transform of the parent body of the joint
	#var parent_body_transform = Transform3D(Basis(rotations[parent_body_name][frame]),Vector3(positions[parent_body_name][frame]))
	# get the rotation of the parent body of the joint
	var parent_body_rotation = Basis(rotations[parent_body_name][frame])
	# get the position of the parent body of the joint
	var parent_body_position = Vector3(positions[parent_body_name][frame])
	# the global position of the joint is the global position of the parent as well as the position of the joint rotated according to the global orientation of the parent body
	var joint_position = parent_body_rotation*Vector3(joint_translations[joint_name])+parent_body_position
	# finally, if the HumanModel mesh is not at (0,0,0), we must account for that translation
	joint_position += get_global_position()
	return joint_position

func find_body_global_position(body_name: String, frame: int) -> Vector3:
	var body_position = Vector3(positions[body_name][frame])
	body_position += get_global_position()
	return body_position
#	skeleton.get_bone_global_pose(skeleton.find_bone(body_to_bone[body])).origin

func find_marker_global_position(marker_name: String, frame: int) -> Vector3:
	var marker_position = Vector3(marker_positions[marker_name][frame])
	marker_position += get_global_position()
	return marker_position

# find the index of the frame for given time and sampling frequency; note that this frame starts at zero
func find_frame(time: float, step: float) -> int:
	return floor(time/step)

# save screen capture where there is no background and the human mesh is a full silhouette, and segment silhouettes for each tracked body
func save_silhouette_masks() -> void:
	# switch mesh material to silhouette mode so that the full body is an unshaded white area in the screen, but save the original material so we can switch back to it afterwards
	var original_shader_material = skin_material.get_next_pass()
	skin_material.set_next_pass(shader_materials["silhouette"])
	
	# switch camera to the one with the right environment (no background, just black) and capture screen
	var cam_standard = get_viewport().get_camera_3d()
	var cam_mask = cam_standard.get_parent().get_node("MaskCamera")
	cam_standard.current = false
	cam_mask.current = true
	# give the dynamic lighting 30 frames to settle to remove reflections on mesh surface
	for i in range(30):
		await get_tree().process_frame
	# make sure the mesh is redrawn after updating shader (probably obsolete if we wait 30 frames anyway, but shouldn't hurt)
	await RenderingServer.frame_post_draw
	# capture the camera view
	var capture = get_viewport().get_texture().get_image()
	
	output.save_image(capture,'output_silhouettes','_silhouette')
	
	# save limb masks for each tracked body
	set_segment_mask_enabled(true)
	# switch the next pass of the mesh material to body mask, where we can hide the irrelevant segments
	skin_material.set_next_pass(shader_materials["body_mask"])
	# loop through bodies that we are tracking and capture and save the segment of each
	for body in tracked_bodies:
		set_segment_index(bone_name_to_idx[body])
		# make sure screen is updated before capturing the camera view
		await RenderingServer.frame_post_draw
		capture = get_viewport().get_texture().get_image()
		
		output.save_image(capture,'output_segments','_'+body)
	# switch segment mask off so the shader can return to normal function
	set_segment_mask_enabled(false)
	
	# switch back to the standard camera
	cam_mask.current = false
	cam_standard.current = true
	
	# switch back to the usual shader material for the next pass
	skin_material.set_next_pass(original_shader_material)

# set if MSK simulation has been run successfully; called from the GUI
func set_simulation_success_state(setting: bool) -> void:
	simulation_successful = setting

# save a screenshot to file
func save_screen_capture(save: bool = true) -> void:
	
	# this will make sure that screen captures are not saved if the necessary steps are not taken first (running an OpenSim simulation and selecting skin mesh parameters)
	if !(mesh_changed and simulation_successful) and demo_mode:
		print('While in demonstration mode, make sure you run the simulation and select a weight and sex for the visual avatar before taking screen captures.')
		return
	
	# give the dynamic lighting 30 frames to settle
	for i in range(30):
		await get_tree().process_frame
	if save:
		var capture = get_viewport().get_texture().get_image()
		output.save_image(capture,'output_photos')
	
		# now that we have saved the normal screen capture, we will also save silhouette of the full body and mesh segments corresponding to the tracked bodies
		await save_silhouette_masks()
	else:
		output.mock_save_image('output_photos')
	
	
	# if we haven't recalculated bounding box since changing skeletal pose, do so now; this way we do not have to recalculate bounding box even when there's no need (i.e., pose hasn't changed)
	if recalculate_bounding_box:
		bounding_box = get_precise_aabb(skin_mesh)
		recalculate_bounding_box = false
	# this will visualize the bounding box for debugging purposes
	#for i in range(8):
	#	var new_sphere = overlay_node.instantiate()
	#	add_child(new_sphere)
#		new_sphere.set_global_position(bounding_box.get_endpoint(i))
	#	new_sphere.visible = true
	
	var boundaries = []
		
	if node_player:
		for joint in joint_names:
			var joint_global_position = find_joint_global_position(joint,current_frame)
			var coord = node_player.find_image_coordinates(joint_global_position)
			var depth = node_player.find_depth_in_camera_view(joint_global_position)
			output.append_value('jp_' + joint + '_x',coord.x)
			output.append_value('jp_' + joint + '_y',coord.y)
			output.append_value('jp_' + joint + '_z',depth)
		# later it might be necessary to add the origin of the 3D model in the global coordinate system to this, because get_bone_global_pose gets the transform w.r.t. the skeleton node
		for body in tracked_bodies:
			#var coord = node_player.find_image_coordinates(skeleton.get_bone_global_pose(skeleton.find_bone(body_to_bone[body])).origin)
			var body_global_position = find_body_global_position(body,current_frame)
			var coord = node_player.find_image_coordinates(body_global_position)
			var depth = node_player.find_depth_in_camera_view(body_global_position)
			output.append_value('bp_' + body + '_x',coord.x)
			output.append_value('bp_' + body + '_y',coord.y)
			output.append_value('bp_' + body + '_z',depth)
		for marker in marker_names:
			var marker_global_position = find_marker_global_position(marker,current_frame)
			var coord = node_player.find_image_coordinates(marker_global_position)
			var depth = node_player.find_depth_in_camera_view(marker_global_position)
			output.append_value('vm_' + marker + '_x',coord.x)
			output.append_value('vm_' + marker + '_y',coord.y)
			output.append_value('vm_' + marker + '_z',depth)
		boundaries = process_aabb(bounding_box,node_player)
	elif node_camera:
		for joint in joint_names:
			var joint_global_position = find_joint_global_position(joint,current_frame)
			var coord = node_camera.unproject_position(joint_global_position)
			var depth = node_camera.get_global_position().distance_to(joint_global_position)
			output.append_value('jp_' + joint + '_x',coord.x)
			output.append_value('jp_' + joint + '_y',coord.y)
			output.append_value('jp_' + joint + '_z',depth)
		# later it might be necessary to add the origin of the 3D model in the global coordinate system to this, because get_bone_global_pose gets the transform w.r.t. the skeleton node
		for body in tracked_bodies:
			#var coord = node_camera.unproject_position(skeleton.get_bone_global_pose(skeleton.find_bone(body_to_bone[body])).origin)
			var body_global_position = find_body_global_position(body,current_frame)
			var coord = node_camera.unproject_position(body_global_position)
			var depth = node_camera.get_global_position().distance_to(body_global_position)
			output.append_value('bp_' + body + '_x',coord.x)
			output.append_value('bp_' + body + '_y',coord.y)
			output.append_value('bp_' + body + '_z',depth)
		for marker in marker_names:
			var marker_global_position = find_marker_global_position(marker,current_frame)
			var coord = node_camera.unproject_position(marker_global_position)
			var depth = node_camera.get_global_position().distance_to(marker_global_position)
			output.append_value('vm_' + marker + '_x',coord.x)
			output.append_value('vm_' + marker + '_y',coord.y)
			output.append_value('vm_' + marker + '_z',depth)
		boundaries = process_aabb(bounding_box,node_camera)
	else:
		print('HumanModel::save_screen_capture() failed because node_player and node_camera are both null')
		assert(false)
		get_tree().quit()
	
	output.append_value('bb_x',boundaries[0])
	output.append_value('bb_y',boundaries[1])
	output.append_value('bb_w',boundaries[2])
	output.append_value('bb_h',boundaries[3])
	
	for coord in generalized_coordinate_names:
		output.append_value('gc_' + coord, generalized_coordinate_values[coord][current_frame])
		
	# check occlusion by casting a ray to all target points and counting the number of collisions
	#var targets = joint_names.duplicate(true)
	#targets.append_array(tracked_bodies)
	#targets.append_array(marker_names)
	for target in joint_names:
		var n_collisions = raycast_to(target)
		var visibility = 1.0/(1.0+n_collisions)
		output.append_value(str('visibility_jp_', target), visibility)
	for target in tracked_bodies:
		var n_collisions = raycast_to(target)
		var visibility = 1.0/(1.0+n_collisions)
		output.append_value(str('visibility_bp_', target), visibility)
	for target in marker_names:
		var n_collisions = raycast_to(target)
		var visibility = 1.0/(1.0+n_collisions)
		output.append_value(str('visibility_vm_', target), visibility)
	#for target in targets:
	#	var n_collisions = raycast_to(target)
	#	var visibility = 1.0/(1.0+n_collisions)
	#	print('Target annotation point ', target, ' has ', str(n_collisions), ' collision detections along the path from camera to the target point. Setting visibility to ', str(visibility))
	#	output.append_value(str('visibility_', target), visibility)
		

# slow-performing function adapted from https://stackoverflow.com/questions/78278490/how-to-get-aabb-of-meshinstance3d-deformed-by-bones-of-a-skeleton3d
# we have to calculate the bounding box of the mesh after it has been deformed by the current pose of the skeleton, because the default inbuilt AABB function returns the non-deformed bounding box of the mesh
func get_precise_aabb(mesh_instance : MeshInstance3D) -> AABB:
	
	#var t1 = Time.get_unix_time_from_system()
	#var bb = utils.get_skeleton_aabb(mesh_instance.get_parent(),mesh_instance,step)
	#var t2 = Time.get_unix_time_from_system()
	#print("GDExtension took ", t2-t1)
	
	#var t3= Time.get_unix_time_from_system()
	
	# we get the parent of the skin mesh, which is the skeleton; required for calculating posed bone transforms
	var skeleton_of_mesh: Skeleton3D = mesh_instance.get_node_or_null(mesh_instance.skeleton)
	# low and high describe the opposite corner defining the bounding box; updated at the end of this function
	var low: Vector3 = Vector3.INF
	var high: Vector3 = -Vector3.INF
	
	# iterate through the number of surfaces (so far this has been 1)
	for surface in mesh_instance.mesh.get_surface_count():
		#print("Surfaces: ", mesh_instance.mesh.get_surface_count())
		# get arrays at index surface (around 44k vertices, exact number depends on morphology)
		var data := mesh_instance.mesh.surface_get_arrays(surface)
		# get vertices from those arrays
		var vertices: Array = data[Mesh.ARRAY_VERTEX]
		var vert_map := {} # to avoid recalculating
		
		#print("Number of vertices: ", len(vertices))
		
		# integrate through the number of vertices in that surface
		for vert_idx in range(0,len(vertices),bb_step):
			var vert = vertices[vert_idx]
			
			# if the vertex has already been added to the map of vertices, continue to next iteration as there's no need to recalculate low and high
			if(vert in vert_map):
				continue
			else:
				vert_map[vert]=null
			
			# if we found skeleton and skin, we calculate the pose-transformed (deformed) position of the vertex; otherwise we do not transform it
			if(skeleton_of_mesh and mesh_instance.skin):
				var bones: Array = data[Mesh.ARRAY_BONES]
				# weights describing how much the vertex follows each bone
				var weights: Array = data[Mesh.ARRAY_WEIGHTS]
				var bone_count := len(weights)/len(vertices)
				var transformed_vert = Vector3.ZERO
				# iterate through the number of bones in the skeleton and calculate the bone-transformed vertex
				for i in bone_count:
					var vertex_bone_weight = weights[vert_idx * bone_count + i]
					
					# if there is no weight, the current vertex isn't affected by that bone and we can carry on to the next bone
					if(!vertex_bone_weight):
						continue
					
					# calculated the transform of the bone and change the position of the vertex accordingly
					var bone_idx = bones[vert_idx * bone_count + i]
					var bind_pose = mesh_instance.skin.get_bind_pose(bone_idx)
					var bone_global_pose = skeleton_of_mesh.get_bone_global_pose(bone_idx)
					transformed_vert += (bone_global_pose * bind_pose * vert) * vertex_bone_weight
				
				vert = transformed_vert
			
			# now check if that bone-transformed vertex extends the bounding box's dimensions
			vert=mesh_instance.global_transform * vert
			
			low.x = vert.x if low.x > vert.x else low.x
			high.x = vert.x if vert.x > high.x else high.x
			
			low.y = vert.y if low.y > vert.y else low.y
			high.y = vert.y if vert.y > high.y else high.y
			
			low.z = vert.z if low.z > vert.z else low.z
			high.z = vert.z if vert.z > high.z else high.z
	
	#var t4 = Time.get_unix_time_from_system()
	#print("GDScript took ", t4-t3)
	
	# return the low corner and the width, height and depth of the 3D bounding box
	return AABB(low, high - low)

# calculates the 2D bounding box coordinates enclosing the skin mesh in the camera viewport; returns [x,y,width,height]
func process_aabb(aabb: AABB, node: Node, padding: int = bb_padding) -> Array:
	# first, get all corners of the AABB bounding box
	var corners = []
	for i in range(8):
		corners.append(aabb.get_endpoint(i))
	
	# then, unproject them to the camera's 2D coordinates
	var corners_2d = []
	for corner in corners:
		corners_2d.append(node.unproject_position(corner))
	
	# finally, find the largest 2D bounding box from these points
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for corner in corners_2d:
		min_x = min(min_x,corner.x)
		max_x = max(max_x,corner.x)
		min_y = min(min_y,corner.y)
		max_y = max(max_y,corner.y)
	
	min_x = floor(min_x)
	max_x = ceil(max_x)
	min_y = floor(min_y)
	max_y = ceil(max_y)
	
	# apply padding
	if padding > 0:
		min_x -= padding
		min_y -= padding
		max_x += padding
		max_y += padding
	
	return [min_x, min_y, max_x-min_x, max_y-min_y]

# get the global position for joint or body by name
func get_position_for(target_name: String) -> Vector3:
	if joint_names.has(target_name):
		return find_joint_global_position(target_name,current_frame)
	elif tracked_bodies.has(target_name):
		return find_body_global_position(target_name,current_frame)
	elif marker_names.has(target_name):
		return find_marker_global_position(target_name,current_frame)
	else:
		printerr("Target name was not found in HumanModel::get_position_for()!")
		get_tree().quit()
		return Vector3()



# cast a ray from the camera origin to the body/joint/point of interest and return the number of colliders encountered on the way
func raycast_to(target_name: String) -> int:
	var raycast = RayCast3D.new()
	add_child(raycast)
	var raycast_origin: Vector3
	if node_player:
		raycast_origin = node_player.get_global_position()
	elif node_camera:
		raycast_origin = node_camera.get_global_position()
	else:
		printerr("ERROR: Neither node_player nor node_camera found in HumanModel::raycast_to(), closing program")
		get_tree().quit()
	raycast.set_global_position(raycast_origin)
	var target_position = get_position_for(target_name)
	# the target position must be calculated in the raycast's local coordinates
	var relative_target_position = target_position-raycast_origin
	raycast.set_target_position(relative_target_position)
	
	raycast.force_raycast_update()
	var n_collisions = 0
	while raycast.get_collider():
		n_collisions += 1
		raycast.add_exception(raycast.get_collider())
		raycast.force_raycast_update()
	
	# delete the raycast once we're done
	raycast.queue_free()
	
	return n_collisions
