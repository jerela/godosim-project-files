extends Node3D

var rng=RandomNumberGenerator.new()

@onready var mesh = $HumanModel
#@onready var env = $EnvironmentManager
@onready var bg = $BackgroundManager
@onready var output = $OutputManager

# the following bunch of variables are read from the configuration file
var save_images: bool = false
var save_csv: bool = false
var max_iterations: int = 0
var iteration: int = 0
var iteration_mode : String
var paths_model: Array = []
var sexes: Array = []
var weights: Array = []
var planar_offset: float = 0.0
var occlusion: String = "none"

var num_weights: int = -1
var num_sexes: int = -1

var num_backgrounds: int = 0
var num_frames: int = 0
var num_skin_textures_male: int = 0
var num_skin_textures_female: int = 0
var num_clothing_textures: int = 0

# iteration parameters in a dictionary of arrays
var parameters: Dictionary = {}

# whether the image generation is finished
var finished: bool = false

var config = ConfigFile.new()

var obstacle_fragmented = load('res://Scenes/ObstacleFragmented.tscn')
var obstacle_windows = load('res://Scenes/ObstacleWindows.tscn')

func _ready() -> void:
	var t1 = Time.get_unix_time_from_system()
	
	rng.set_seed(0)
	read_config('config.cfg')
	if occlusion == 'fragmented':
		var obstacle = obstacle_fragmented.instantiate()
		add_child(obstacle)
	elif occlusion == 'windows':
		var obstacle = obstacle_windows.instantiate()
		add_child(obstacle)
	
	prepare_photoshoot()
	
	while !finished:
		await run_photoshoot(iteration)
		iteration += 1
		
		if iteration == len(parameters['frame']) or iteration==max_iterations:
			if save_csv:
				output.write_coordinate_csv()
				for i in range(parameters.size()):
					output.assign_metadata(parameters.keys()[i], parameters.values()[i])
				output.write_metadata_csv()
			finished = true

	var t2 = Time.get_unix_time_from_system()
	var duration = t2-t1
	var hours = floor(duration/3600.0)
	var minutes = floor((duration-hours*3600.0)/60.0)
	var seconds = round(duration - hours*3600.0 - minutes*60.0)
	print("Generating ", iteration, " images took ", hours, " hours, ", minutes, " minutes, and ", seconds, " seconds.")	
	finish()
	
func read_config(cfg_name: String) -> void:
	var err = config.load(str("user://Config/", cfg_name))
	if err != OK:
		print('config reading failed')
		return
	
	iteration = config.get_value('generate', 'first_image_index')
	max_iterations = config.get_value('generate','max_image_number') + iteration
	save_images = config.get_value('generate','save_images')
	save_csv = config.get_value('generate','save_csv')
	iteration_mode = config.get_value('generate','iteration_mode')
	paths_model = config.get_value('generate','paths_model')
	sexes = config.get_value('generate','sexes')
	weights = config.get_value('generate','weights')
	planar_offset = config.get_value('generate','planar_offset')
	occlusion = config.get_value('generate','occlusion')
	

# run all one-time operations in preparation for image generation
func prepare_photoshoot() -> void:
	# run OpenSim simulations; we want to run them first for all model-motion combinations so we can just access them later when switching models without having to rerun SkeletonTracker
	mesh.set_tracked_bodies(config.get_value('generate', 'bodies'))
	for i in range(len(paths_model)):
		mesh.set_model(paths_model[i])
		mesh.set_motion(config.get_value('generate','path_motion'))
		mesh.run_simulation()
	mesh.change_mesh('male','zero')
	# make sure the dictionary mapping body/bone names to their indices in the armature is populated (has to be done after change_mesh, so that skeleton is not null in HumanModel)
	mesh.populate_tracked_body_indices()
	# prepare parameters arrays for setting different image conditions
	prepare_parameters()
	print('params prepared')
	
# create arrays containing the settings for each image
func prepare_parameters() -> void:
	
	num_sexes = len(sexes)
	num_weights = len(weights)
	
	num_frames = mesh.get_num_frames()
	num_clothing_textures = mesh.get_num_clothing_textures()
	mesh.sex = 'male'
	num_skin_textures_male = mesh.get_num_skin_textures()
	mesh.sex = 'female'
	num_skin_textures_female = mesh.get_num_skin_textures()
	
	var num_skins = min(num_skin_textures_male, num_skin_textures_female)
	
	#num_environments = $EnvironmentManager.get_num_environments()
	num_backgrounds = $BackgroundManager.get_num_backgrounds()
	
	var _texture_labels = mesh.change_mesh(sexes[0],weights[0])

	var environs_idx = []
	var frames = []
	var sexes_idx = []
	var weights_idx = []
	var skins_idx = []
	var clothes_idx = []
	var xrs = []
	var yrs = []
	var fovs = []
	if iteration_mode == 'full':
		# holding this information is memory-heavy, better alternatives required
		for sex in range(num_sexes):
			for weight in range(num_weights):
				for background in range(num_backgrounds):
					for frame in range(num_frames):
						for clothing in range(num_clothing_textures):
							for xr in range(-80,80,20):
								for yr in range(-180,180,20):
									for fov in range(30,120,15):
										environs_idx.append(background)
										sexes_idx.append(sex)
										weights_idx.append(weight)
										frames.append(frame)
										clothes_idx.append(clothing)
										xrs.append(xr)
										yrs.append(yr)
										fovs.append(fov)
	elif iteration_mode == 'poses-multiview':
		var iter_idx = 0
		for frame in range(num_frames):
			for view in range(10):
				iter_idx += 1
				xrs.append(rng.randi_range(-80,80))
				yrs.append(rng.randi_range(-180,180))
				fovs.append(rng.randi_range(30,120))
				frames.append(frame)
				sexes_idx.append(iter_idx%num_sexes)
				weights_idx.append(iter_idx%num_weights)
				environs_idx.append(iter_idx%num_backgrounds)
				clothes_idx.append(iter_idx%num_clothing_textures)
				skins_idx.append(iter_idx%num_skins)
	elif iteration_mode == 'poses-singleview':
		var iter_idx = 0
		for frame in range(num_frames):
			iter_idx += 1
			xrs.append(rng.randi_range(-80,80))
			yrs.append(rng.randi_range(-180,180))
			fovs.append(rng.randi_range(30,120))
			frames.append(frame)
			sexes_idx.append(iter_idx%num_sexes)
			weights_idx.append(iter_idx%num_weights)
			environs_idx.append(iter_idx%num_backgrounds)
			clothes_idx.append(iter_idx%num_clothing_textures)
			skins_idx.append(iter_idx%num_skins)
	# "level" rotates around the subject around the vertical axis but limits how high or low the camera is compared to the subject
	elif iteration_mode == 'level':
		var iter_idx = 0
		for frame in range(num_frames):
			iter_idx += 1
			xrs.append(rng.randi_range(-15,15))
			yrs.append(rng.randi_range(-180,180))
			fovs.append(rng.randi_range(30,120))
			frames.append(frame)
			sexes_idx.append(iter_idx%num_sexes)
			weights_idx.append(iter_idx%num_weights)
			environs_idx.append(iter_idx%num_backgrounds)
			clothes_idx.append(iter_idx%num_clothing_textures)
			skins_idx.append(iter_idx%num_skins)
	# "planar" is like level, but only generates images of the motion on a plane on both sides; the exact plane depends on planar_offset
	elif iteration_mode == 'planar':
		var iter_idx = 0
		for frame in range(num_frames):
			iter_idx += 1
			xrs.append(rng.randi_range(-15,15))
			yrs.append(rng.randi_range(-30,30) + planar_offset + rng.randi_range(0,1)*180)
			fovs.append(rng.randi_range(30,120))
			frames.append(frame)
			sexes_idx.append(iter_idx%num_sexes)
			weights_idx.append(iter_idx%num_weights)
			environs_idx.append(iter_idx%num_backgrounds)
			clothes_idx.append(iter_idx%num_clothing_textures)
			skins_idx.append(iter_idx%num_skins)
	
				
	parameters['sex'] = sexes_idx
	parameters['weight'] = weights_idx
	parameters['background'] = environs_idx
	parameters['frame'] = frames
	parameters['clothing'] = clothes_idx
	parameters['skin'] = skins_idx
	parameters['xrot'] = xrs
	parameters['yrot'] = yrs
	parameters['fov'] = fovs
	
	print('Ready to iterate ', len(environs_idx), ' images!')
	

func run_photoshoot(iter: int) -> void:
	print('Running photoshoot for iteration ', iter, '.')
	
	# reload environment only if necessary
	if parameters['background'][iter] != $BackgroundManager.get_current_background_index():
		$BackgroundManager.set_background_by_index(parameters['background'][iter])

	# change the morphology of the mesh only if necessary
	var iterated_sex = sexes[parameters['sex'][iter]]
	var iterated_weight = weights[parameters['weight'][iter]]	
	if not (mesh.sex == iterated_sex and mesh.weight == iterated_weight):
		# also, whenever we change the mesh, we should call run_simulation() to make sure we access the rotations and positions for the current model
		var model_idx = parameters['weight'][iter] + num_weights*parameters['sex'][iter]
		var iterated_model = paths_model[model_idx]
		mesh.set_model(iterated_model)
		mesh.change_mesh(iterated_sex,iterated_weight)
		mesh.run_simulation()
		# center the mesh even if pelvis translational coordinates are non-zero
		mesh.set_position(-mesh.get_current_root_position())
		#print('Iterated sex: ', iterated_sex)
		#print('Iterated weight: ', iterated_weight)
		#print('Iterated model: ', iterated_model)
	

	# set the human mesh to the correct frame of the motion data
	var frame = parameters['frame'][iter]
	mesh.set_current_frame(frame)
	print('iteration ', str(iter), ', frame ', str(frame))
	mesh.visualize_frame(frame)

	# change clothing
	mesh.set_clothing_texture_by_index(parameters['clothing'][iter])
	# change skin
	mesh.set_skin_texture_by_index(parameters['skin'][iter])

	# set camera angle
	$Lever.set_rotation_degrees(Vector3(parameters['xrot'][iter],parameters['yrot'][iter],0))
	
	# set camera field of view (FOV) for all cameras
	set_children_fov($Lever,parameters['fov'][iter])
	
	if save_images:
		await capture_image()
	else:
		for i in range(30):
			await get_tree().process_frame


# save the current camera view and do other possible operations related to it
func capture_image() -> void:
	await mesh.save_screen_capture()

# set the FOV for all cameras under parent node
func set_children_fov(parent: Node,fov: float) -> void:
	for cam in parent.get_children():
		cam.set_fov(fov)

# once generation is done, wait 10 seconds and close program
func finish() -> void:
	print('Program finished! Closing automatically in 10 seconds.')
	await get_tree().create_timer(10).timeout
	get_tree().quit()
	return
