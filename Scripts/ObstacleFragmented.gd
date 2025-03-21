extends Node3D

var pebble_res = preload("res://Scenes/ObstaclePebble.tscn")

var pebble_radius_min = 0.05
var pebble_radius_max = 0.15
var sphere_radius_min = 1.8
var sphere_radius_max = 2.2
var pebble_density = 80

var sphere_radius_mean = (sphere_radius_min+sphere_radius_max)/2

func _ready() -> void:
	read_config('config.cfg')
	generate_pebbles()
	
func read_config(cfg_name: String) -> void:
	var config = ConfigFile.new()
	var err = config.load(str("user://Config/", cfg_name))
	if err != OK:
		print('config reading failed')
		return
	
	pebble_density = config.get_value('occlusion-fragmented','pebble_density')
	
	pebble_radius_min = config.get_value('occlusion-fragmented','pebble_radius_min')
	pebble_radius_max = config.get_value('occlusion-fragmented','pebble_radius_max')	
	
	sphere_radius_min = config.get_value('occlusion-fragmented','sphere_radius_min')
	sphere_radius_max = config.get_value('occlusion-fragmented','sphere_radius_max')
	sphere_radius_mean = (sphere_radius_min+sphere_radius_max)/2

func _physics_process(_delta: float) -> void:
	# make the pebbles slowly rotate non-periodically
	$PebbleContainer.set_rotation($PebbleContainer.get_rotation()+Vector3(0.023,0.017,0.011))

func generate_pebbles() -> void:
	# because the area of a sphere is related to the square of the radius, we must make the number of pebbles to spread on the surface of the sphere relative to the square of the radius in order to keep the coverage similar between different radii
	var n = round(pebble_density*sphere_radius_mean*sphere_radius_mean)
	for i in range(n):
		generate_pebble()
		
func generate_pebble() -> void:
	var pebble = pebble_res.instantiate()
	$PebbleContainer.add_child(pebble)
	
	# vary pebble size
	pebble.radius = randf_range(pebble_radius_min,pebble_radius_max)
	# vary pebble shape
	pebble.material.set_shader_parameter("vert_x_factor", randf_range(0.5,1.5))
	pebble.material.set_shader_parameter("vert_y_factor", randf_range(0.5,1.5))
	pebble.material.set_shader_parameter("vert_z_factor", randf_range(0.5,1.5))
	
	# vary pebble colour
	pebble.material.set_shader_parameter("albedo", Vector4(randf_range(0.0,1.0),randf_range(0.0,1.0),randf_range(0.0,1.0),1.0))
	
	# vary pebble rotation
	pebble.set_rotation(Vector3(randf_range(-PI,PI),randf_range(-PI,PI),randf_range(-PI,PI)))
	
	# set pebble position
	var r = randf_range(sphere_radius_min, sphere_radius_max)
	var polar = randf_range(0,PI)
	var azimuthal = randf_range(0,2*PI)
	var x = r*sin(polar)*cos(azimuthal)
	var y = r*sin(polar)*sin(azimuthal)
	var z = r*cos(polar)
	pebble.set_global_position(Vector3(x,y,z))
	

	
	
	
