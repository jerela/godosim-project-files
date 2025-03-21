extends Node

func _ready():
	# make sure there is a config file, and if there isn't, create one
	validate_config()
	# go to image generation, or if the cmd line argument is set, the demo scene
	select_next_scene()

# read cmd line args to decide which scene to go to next
func select_next_scene() -> void:
	var arguments = Array(OS.get_cmdline_args())
	if arguments.has("-demo"):
		print("Entering demo scene")
		get_tree().change_scene_to_file("res://Scenes/Demo.tscn")
	else:
		print("Starting image generation program.")
		# we're using call_deferred() here to make sure the main loop is done before we remove the parent scene
		get_tree().change_scene_to_file.call_deferred("res://Scenes/Generate.tscn")

# make sure there is a config file
func validate_config() -> void:
	var config = ConfigFile.new()
	# If we find the config file, all is good. If we don't because the file wasn't found, we'll create one.
	var err = config.load("user://Config/config.cfg")
	if err == OK:
		print("Found config.cfg in ", OS.get_user_data_dir(), "/Config/config.txt")
	elif err == ERR_FILE_NOT_FOUND:
		print("config.cfg not found in directory ", OS.get_user_data_dir(), "/Config/")
		check_config_directory()
		create_config_file()
	else:
		print("Error code ", str(err), " while trying to open config.cfg in directory ", OS.get_user_data_dir(), "/Config/")
	return

# make sure the Config directory exists in user data path
func check_config_directory():
	if !DirAccess.dir_exists_absolute("user://Config"):
		print("Directory ", OS.get_user_data_dir(), "/Config did not exist, creating it...")
		DirAccess.make_dir_recursive_absolute("user://Config")

# creates a dummy config file for the user to fill with their filesystem-specific values
func create_config_file() -> void:
	print("Creating a config file...")
	
	var config = ConfigFile.new()

	# generate dictionaries with key-value pairs to populate the config file
	var cfg_paths: Dictionary = {
		"path_output_annotations": str(OS.get_user_data_dir(), "/Output/annotations"),
		"path_output_images_photos": str(OS.get_user_data_dir(), "/Output/images"),
		"path_output_images_silhouette_masks": str(OS.get_user_data_dir(), "/Output/silhouettes"),
		"path_output_images_segment_masks": str(OS.get_user_data_dir(), "/Output/segments")
	}
	
	var cfg_project_settings: Dictionary = {
		"screen_resolution": Vector2(1024, 1024)
	}
	
	var cfg_external_data: Dictionary = {
		"path_textures_skin_male": "DRIVE:/Users/YourUserNameGoesHere/Documents/external-data/Skin-male/",
		"path_textures_skin_female": "DRIVE:/Users/YourUserNameGoesHere/Documents/external-data/Skin-female/",
		"path_textures_clothing": "DRIVE:/Users/YourUserNameGoesHere/Documents/external-data/Clothing/",
		"path_human_mesh": "DRIVE:/Users/YourUserNameGoesHere/Documents/external-data/Meshes/",
		"path_hdri": "DRIVE:/Users/YourUserNameGoesHere/Documents/external-data/HDRI/"
	}
	
	var cfg_skeletontracker: Dictionary = {
		"persistent_musculoskeletal_simulation_data": true
	}
	
	var cfg_generate: Dictionary = {
		"first_image_index": 0,
		"max_image_number": 10,
		"save_images": true,
		"save_csv": true,
		"iteration_mode": "level",
		"occlusion": "none",
		"lighting": "normal",
		"planar_offset": 90,
		"bodies": ["pelvis", "femur_r", "tibia_r", "calcn_r", "femur_l", "tibia_l", "calcn_l", "torso", "humerus_r", "radius_r", "hand_r", "humerus_l", "radius_l", "hand_l"],
		"path_motion": "DRIVE:/Users/YourUserNameGoesHere/Documents/Godosim-assets/motion_files/running.mot",
		"weights": ["plus2", "zero", "minus2", "plus2", "zero", "minus2"],
		"sexes": ["male", "male", "male", "female", "female", "female"],
		"paths_model": ["DRIVE:/Users/YourUserNameGoesHere/Documents/Godosim-assets/opensim_models/Godosim_Hamner_male_plus2.osim", "DRIVE:/Users/YourUserNameGoesHere/Documents/Godosim-assets/opensim_models/Godosim_Hamner_male_zero.osim", "DRIVE:/Users/YourUserNameGoesHere/Documents/Godosim-assets/opensim_models/Godosim_Hamner_male_minus2.osim", "DRIVE:/Users/YourUserNameGoesHere/Documents/Godosim-assets/opensim_models/Godosim_Hamner_female_plus2.osim", "DRIVE:/Users/YourUserNameGoesHere/Documents/Godosim-assets/opensim_models/Godosim_Hamner_female_zero.osim", "DRIVE:/Users/YourUserNameGoesHere/Documents/Godosim-assets/opensim_models/Godosim_Hamner_female_minus2.osim"]
	}
	
	var cfg_occlusion_fragmented: Dictionary = {
		"pebble_radius_min": 0.05,
		"pebble_radius_max": 0.15,
		"sphere_radius_min": 1.8,
		"sphere_radius_max": 2.2,
		"pebble_density": 80
	}
	
	var cfg_defaults: Dictionary = {
		"paths": cfg_paths,
		"project_settings": cfg_project_settings,
		"external_data": cfg_external_data,
		"skeletontracker": cfg_skeletontracker,
		"generate": cfg_generate,
		"occlusion_fragmented": cfg_occlusion_fragmented
	}
	
	# populate the config file
	for section in cfg_defaults:
		for key in cfg_defaults[section]:
			config.set_value(section, key, cfg_defaults[section][key])

	# save config file and report if we succeeded
	var err = config.save("user://Config/config.cfg")
	if err == OK:
		print("... config file saved to ", OS.get_user_data_dir(), "/Config/config.txt")
	else:
		print("... failed to save config file to ", OS.get_user_data_dir(), "/Config/config.txt")
		printerr("Error! Config was not found and saving new config was not successful. Make sure the path exists. Closing program.")
		get_tree().quit()

	return
