extends Node3D

@export var allow_mouse_input = false
@export var node_gui: Node
@export var node_mesh: Node
@export var free_roam = true
@export var gui_enabled = false

var cameras = []

var pitch = 0
var yaw = 0


func _ready():
	update_camera()
	update_gui_state()
	cameras.append($Lever/LeverCam)
	cameras.append($FreeRoam/FreeRoamCamera)

func set_camera_projection(index: int) -> void:
	for camera in cameras:
		camera.set_projection(index)

func set_camera_fov(value: float) -> void:
	for camera in cameras:
		camera.set_fov(value)

func update_gui_state() -> void:
	if gui_enabled:
		if node_gui:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			node_gui.visible = true
	else:
		if node_gui:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			node_gui.visible = false

func _physics_process(delta: float) -> void:
	
	if allow_mouse_input and !gui_enabled:
		if free_roam:
			var movement = Input.get_vector("move_back", "move_forward", "move_left", "move_right")
			if movement.length_squared() > 0:
				$FreeRoam.translate_object_local(Vector3(movement.x*5*delta, 0, movement.y*5*delta))
		else:
		
			if Input.is_action_pressed("move_back"):
				$Lever/LeverCam.set_position($Lever/LeverCam.get_position()+Vector3(0,0,delta))
			if Input.is_action_pressed("move_forward"):
				$Lever/LeverCam.set_position($Lever/LeverCam.get_position()+Vector3(0,0,-delta))
		
	
		
	if Input.is_action_just_pressed("toggle_gui"):
		gui_enabled = !gui_enabled
		update_gui_state()
		
	if !gui_enabled:
		
		if Input.is_action_just_pressed("capture_screen"):
			node_mesh.save_screen_capture()
	
		if Input.is_action_just_pressed("save_projections"):
			node_mesh.output.write_coordinate_csv()
		
		if Input.is_action_just_pressed("switch_camera_mode"):
			free_roam = !free_roam
			update_camera()
			
		if Input.is_action_just_pressed("cam_center"):
			$FreeRoam.set_global_position(Vector3(0.0,0.0,0.0))
			pitch = 0
			yaw = 0
			$FreeRoam.set_rotation(Vector3(0,yaw,pitch))
		elif Input.is_action_just_pressed("cam_rotate_left"):
			yaw += PI/4
			$FreeRoam.set_rotation(Vector3(0,yaw,pitch))
		elif Input.is_action_just_pressed("cam_rotate_right"):
			yaw -= PI/4
			$FreeRoam.set_rotation(Vector3(0,yaw,pitch))
		elif Input.is_action_just_pressed("cam_translate_x_plus"):
			var prev_pos = $FreeRoam.get_global_position()
			$FreeRoam.set_global_position(Vector3(prev_pos.x + 0.5, prev_pos.y, prev_pos.z))
		elif Input.is_action_just_pressed("cam_translate_x_minus"):
			var prev_pos = $FreeRoam.get_global_position()
			$FreeRoam.set_global_position(Vector3(prev_pos.x - 0.5, prev_pos.y, prev_pos.z))
		elif Input.is_action_just_pressed("cam_translate_y_plus"):
			var prev_pos = $FreeRoam.get_global_position()
			$FreeRoam.set_global_position(Vector3(prev_pos.x, prev_pos.y + 0.25, prev_pos.z))
		elif Input.is_action_just_pressed("cam_translate_y_minus"):
			var prev_pos = $FreeRoam.get_global_position()
			$FreeRoam.set_global_position(Vector3(prev_pos.x, prev_pos.y - 0.25, prev_pos.z))
		elif Input.is_action_just_pressed("cam_translate_z_plus"):
			var prev_pos = $FreeRoam.get_global_position()
			$FreeRoam.set_global_position(Vector3(prev_pos.x, prev_pos.y, prev_pos.z + 0.5))
		elif Input.is_action_just_pressed("cam_translate_z_minus"):
			var prev_pos = $FreeRoam.get_global_position()
			$FreeRoam.set_global_position(Vector3(prev_pos.x, prev_pos.y, prev_pos.z - 0.5))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and !gui_enabled and allow_mouse_input:
		if free_roam:
			yaw += -event.relative.x/200
			pitch += -event.relative.y/200
			$FreeRoam.set_rotation(Vector3(0,yaw,pitch))
		else:
			var cam_rotation = $Lever.get_rotation()
			$Lever.set_rotation(cam_rotation+Vector3(event.relative.y/200,event.relative.x/200,0))
			if Input.is_action_pressed("mouse_left"):
				#var x_modifier = cos(deg_to_rad(cam_rotation.y))
				var y_modifier = cos(deg_to_rad(cam_rotation.x))
				#var z_modifier = sin(deg_to_rad(cam_rotation.y))
				$Lever.set_position($Lever.get_position()-Vector3(0,event.relative.y*y_modifier*0.1,0))

func update_camera() -> void:
	if free_roam:
		$Lever/LeverCam.current = false
		$FreeRoam/FreeRoamCamera.current = true
	else:
		$Lever/LeverCam.current = true
		$FreeRoam/FreeRoamCamera.current = false

# allows the player object to be called like Camera node's unproject_position() function, in which case the player node will just use its child camera's unproject_position() function
func unproject_position(pos: Vector3) -> Vector2:
	return find_image_coordinates(pos)

# return the input 3D position in the 2D coordinates of the camera viewport, or "image coordinates"
func find_image_coordinates(pos: Vector3) -> Vector2:
	if free_roam:
		return $FreeRoam/FreeRoamCamera.unproject_position(pos)
	else:
		return $Lever/LeverCam.unproject_position(pos)

func find_depth_in_camera_view(target: Vector3) -> float:
	if free_roam:
		return $FreeRoam/FreeRoamCamera.get_global_position().distance_to(target)
	else:
		return $Lever/LeverCam.get_global_position().distance_to(target)
