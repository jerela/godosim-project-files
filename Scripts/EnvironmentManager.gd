extends Node3D


var env_paths = {
	"instructions": "res://Scenes/EnvInstructions.tscn",
	"blank": "res://Scenes/EnvBlank.tscn",
	"grey": "res://Scenes/EnvBlack.tscn"
}

var current_env_idx = 0

func _ready() -> void:
	set_environment('instructions')

# returns the index of the current environment
func get_current_environment_index() -> int:
	return current_env_idx

# returns the number of environments
func get_num_environments() -> int:
	return len(env_paths)

# toggle whether the visualization of the coordinate axes is visible
func toggle_coordinate_axes(setting: bool) -> void:
	$CoordinateAxes.visible = setting

# set environment by its name, e.g., "temple"
func set_environment(key: String) -> String:
	clear_environments()
	
	var new_env = load(env_paths[key])
	var instance = new_env.instantiate()
	$Environments.add_child(instance)
	
	# find origin, if one exists
	var instance_children = instance.get_children()
	for child in instance_children:
		if child.get_name() == "Origin":
			var origin = child.get_position()
			instance.set_global_position(instance.get_global_position()-origin)
			break
	
	return key

func clear_environments() -> void:
	for child in $Environments.get_children():
		child.queue_free()

func switch_environment(direction: int) -> String:
	current_env_idx += direction
	var keys = env_paths.keys()
	if current_env_idx < 0:
		current_env_idx += keys.size()
	elif current_env_idx > keys.size()-1:
		current_env_idx -= keys.size()
	set_environment(keys[current_env_idx])
	return keys[current_env_idx]
	
# set environment by its index
func set_environment_by_index(idx: int) -> void:
	clear_environments()
	
	var new_env = load(env_paths.values()[idx])
	var instance = new_env.instantiate()
	$Environments.add_child(instance)
	
	current_env_idx = idx
	
	# find origin, if one exists
	var instance_children = instance.get_children()
	for child in instance_children:
		if child.get_name() == "Origin":
			var origin = child.get_position()
			instance.set_global_position(instance.get_global_position()-origin)
			break
	
