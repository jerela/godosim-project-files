extends Node3D

@onready var env = $WorldEnvironment

@onready var background_file_names = []
var path_hdris: String

var current_bg_idx = 0

# returns the index of the current background
func get_current_background_index() -> int:
	return current_bg_idx

# switches background to the previous or next one, assuming direction is -1 or 1
func switch_background(direction: int) -> void:
	current_bg_idx += direction
	if current_bg_idx < 0:
		current_bg_idx += get_num_backgrounds()
	elif current_bg_idx > get_num_backgrounds()-1:
		current_bg_idx -= get_num_backgrounds()
	set_background(background_file_names[current_bg_idx])


func _ready() -> void:
	read_config("config.cfg")
	set_background(background_file_names[0])

# read config file, and based on specified external path of HDRI backgrounds and lighting mode, populate an array of background file names and set the proper environment lighting
func read_config(cfg_name: String) -> void:
	var config = ConfigFile.new()
	var err = config.load(str("user://Config/", cfg_name))
	if err != OK:
		print('config reading failed in BackgroundManager::read_config()')
		return
	# store the names of HDRI background files in an array so we can assign them later using those names (and path)
	path_hdris = config.get_value('external_data', 'path_hdri')
	var files = DirAccess.get_files_at(path_hdris)
	print('BackgroundManager found ', len(files), ' files at external HDRI path ', path_hdris)
	for file_name in files:
		background_file_names.append(file_name)
	# set lighting settings
	var lighting = config.get_value('generate','lighting')
	if lighting == "normal":
		env.set_environment(load('res://Environments/BackgroundNormalEnvironment.tres'))
	elif lighting == "low":
		env.set_environment(load('res://Environments/BackgroundLowLightEnvironment.tres'))
	else:
		assert(false, 'ERROR: lighting must have a valid value')

func get_num_backgrounds() -> int:
	return len(background_file_names)

# set background by its index in the array of background file names
func set_background_by_index(idx: int) -> void:
	set_background(background_file_names[idx])

# set background by its file name
func set_background(file_name: String) -> void:
	print('Loading background image ', str(path_hdris.path_join(file_name)))
	var image = Image.load_from_file(str(path_hdris.path_join(file_name)))
	var texture = ImageTexture.create_from_image(image)
	env.environment.get_sky().get_material().set_panorama(texture)
