extends Node3D

func _ready() -> void:
	variate()
	
func variate() -> void:
	for face in $WindowContainer.get_children():
		for tile in face.get_children():
			var alpha = randf_range(0.0,1.0)
			# if alpha is more than 0.9, we set it to opaque as it's close to it anyway; set_use_collision for raycast-enabled visibility detection of locations in the skin mesh
			if alpha > 0.9:
				alpha = 1.0
				tile.set_use_collision(true)
			else:
				tile.set_use_collision(false)
			tile.set_instance_shader_parameter("albedo", Vector4(randf_range(0.0,1.0),randf_range(0.0,1.0),randf_range(0.0,1.0),alpha))

func _physics_process(_delta: float) -> void:
	$WindowContainer.set_rotation($WindowContainer.get_rotation()+Vector3(0.023,0.017,0.011))
