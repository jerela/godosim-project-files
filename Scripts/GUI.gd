extends Control

@export var node_mesh : Node
@export var node_env : Node
@export var node_player : Node

# from HumanModel
func set_motion_frame(current_frame: int, max_frame: int, current_time: float, max_time: float) -> void:
	$PanelContainer/TabBar/Motion/VBoxContainer/FrameControlPanel/VBoxContainer/HBoxContainer/PanelContainer/HBoxContainer/CurrentFrameIndicator.set_text(str(current_frame))
	$PanelContainer/TabBar/Motion/VBoxContainer/FrameControlPanel/VBoxContainer/HBoxContainer/PanelContainer/HBoxContainer/MaxFrameIndicator.set_text(str(max_frame))
	$PanelContainer/TabBar/Motion/VBoxContainer/FrameControlPanel/VBoxContainer/HBoxContainer3/PanelContainer/HBoxContainer/CurrentTimeIndicator.set_text(str(current_time))
	$PanelContainer/TabBar/Motion/VBoxContainer/FrameControlPanel/VBoxContainer/HBoxContainer3/PanelContainer/HBoxContainer/MaxTimeIndicator.set_text(str(max_time))
	$PanelContainer/TabBar/Motion/VBoxContainer/FrameControlPanel/VBoxContainer/PanelContainer/FrameSlider.set_min(1)
	$PanelContainer/TabBar/Motion/VBoxContainer/FrameControlPanel/VBoxContainer/PanelContainer/FrameSlider.set_value(current_frame)
	$PanelContainer/TabBar/Motion/VBoxContainer/FrameControlPanel/VBoxContainer/PanelContainer/FrameSlider.set_max(max_frame)
	
func enable_frame_navigation() -> void:
	for button in $PanelContainer/TabBar/Motion/VBoxContainer/FrameControlPanel/VBoxContainer/HBoxContainer2.get_children():
		button.disabled = false

func _ready() -> void:
	$PanelContainer/TabBar/Camera/VBoxContainer/ProjectionPanel/HBoxContainer/ProjectionList.select(0)

func _on_previous_skin_button_pressed() -> void:
	var texture_label = node_mesh.switch_skin_texture(-1)
	$PanelContainer/TabBar/Actor/VBoxContainer/SkinPanel/HBoxContainer/PanelContainer/HBoxContainer/CurrentTextureLabel.text = texture_label


func _on_next_skin_button_pressed() -> void:
	var texture_label = node_mesh.switch_skin_texture(1)
	$PanelContainer/TabBar/Actor/VBoxContainer/SkinPanel/HBoxContainer/PanelContainer/HBoxContainer/CurrentTextureLabel.text = texture_label


func _on_fov_slider_value_changed(value: float) -> void:
	$PanelContainer/TabBar/Camera/VBoxContainer/FOVPanel/HBoxContainer/PanelContainer/HBoxContainer/FOVLabel.set_text(str(value) + "°")
	node_player.set_camera_fov(value)


func _on_projection_list_item_selected(index: int) -> void:
	node_player.set_camera_projection(index)


func _on_reset_camera_button_pressed() -> void:
	$PanelContainer/TabBar/Camera/VBoxContainer/FOVPanel/HBoxContainer/PanelContainer/HBoxContainer/FOVSlider.value = 75
	$PanelContainer/TabBar/Camera/VBoxContainer/FOVPanel/HBoxContainer/PanelContainer/HBoxContainer/FOVLabel.set_text(str(75) + "°")
	$PanelContainer/TabBar/Camera/VBoxContainer/ProjectionPanel/HBoxContainer/ProjectionList.select(0)
	node_player.set_camera_projection(0)
	node_player.set_camera_fov(75)


func _on_set_model_button_pressed() -> void:
	node_mesh.set_model($PanelContainer/TabBar/Motion/VBoxContainer/ModelPanel/HBoxContainer/ModelFilePath.get_text())

func _on_set_motion_button_pressed() -> void:
	node_mesh.set_motion($"PanelContainer/TabBar/Motion/VBoxContainer/MotionPanel/HBoxContainer/MotionFilePath".get_text())

# when we press "run simulation", Godosim retrieves all the necessary data for visualizing the simulation
func _on_run_simulation_button_pressed() -> void:
	# if simulation is run successfully, enable navigation through motion frames and tell HumanModel that it was a success
	if node_mesh.run_simulation():
		node_mesh.go_to_frame(0)
		enable_frame_navigation()
		node_mesh.set_simulation_success_state(true)
	else:
		node_mesh.set_simulation_success_state(false)

# play the visualization if it's paused when the button is pressed
func _on_play_motion_button_pressed() -> void:
	node_mesh.play_visualization()

# pause the visualization if the button is pressed
func _on_pause_motion_button_pressed() -> void:
	node_mesh.pause_visualization()

# if we press next frame or previous frame buttons, we jump one frame forward or backward and pause the visualization
func _on_previous_frame_button_pressed() -> void:
	node_mesh.pause_visualization()
	node_mesh.switch_frame(-1)

func _on_next_frame_button_pressed() -> void:
	node_mesh.pause_visualization()
	node_mesh.switch_frame(1)

# when the frame slider value is changed (ranges between 1 and N-1), we set the visualization to frame value-1 (ensuring that 1 on the slider corresponds to the first frame at index 0)
func _on_frame_slider_value_changed(value: int) -> void:
	node_mesh.go_to_frame(value-1)

# when zero frame button is pressed, we return the visualization to the first frame (frame 0)
func _on_zero_button_pressed() -> void:
	node_mesh.go_to_frame(0)

# when the loop motion button is toggled, we set its new value to loop_motion variable of HumanModel
func _on_loop_motion_button_pressed() -> void:
	node_mesh.set_loop_motion($PanelContainer/TabBar/Motion/VBoxContainer/FrameControlPanel/VBoxContainer/HBoxContainer2/LoopMotionButton.button_pressed)

# when we press this button, we let Godosim know which OpenSim bodies will be used for getting the rotations and translations in the simulation
func _on_set_tracked_bodies_button_pressed() -> void:
	var tracked_bodies_unformatted = $PanelContainer/TabBar/Motion/VBoxContainer/TrackedBodiesPanel/HBoxContainer/TrackedBodies.get_text()
	node_mesh.set_tracked_bodies(tracked_bodies_unformatted.split(","))

# whenever we select an item on the list of weights and sexes, we sent the information to HumanModel (see the below function update_weight_and_sex() for details)
func _on_weight_list_item_selected(_index: int) -> void:
	update_weight_and_sex()

func _on_sex_list_item_selected(_index: int) -> void:
	update_weight_and_sex()
	
# called whenever weight or sex is changed in the GUI, this changes to the desired skin mesh and updates the GUI label
func update_weight_and_sex() -> void:
	# this returns an array of selected indices, so we just assume only one item is selected and pick that index
	var weight_selection = $PanelContainer/TabBar/Actor/VBoxContainer/WeightPanel/HBoxContainer/WeightList.get_selected_items()
	var sex_selection = $PanelContainer/TabBar/Actor/VBoxContainer/SexPanel/HBoxContainer/SexList.get_selected_items()
	if weight_selection.size() == 1 and sex_selection.size() == 1:
		sex_selection = sex_selection[0]	
		weight_selection = weight_selection[0]
		var texture_labels = node_mesh.change_mesh_by_index(sex_selection,weight_selection)
		$PanelContainer/TabBar/Actor/VBoxContainer/SkinPanel/HBoxContainer/PanelContainer/HBoxContainer/CurrentTextureLabel.text = texture_labels[0]
		$PanelContainer/TabBar/Actor/VBoxContainer/ClothesPanel/HBoxContainer/PanelContainer/HBoxContainer/CurrentClothingLabel.text = texture_labels[1]

# when the overlay button is toggled, we switch between hiding and showing OpenSim body origins as overlaid circles
func _on_overlay_check_button_toggled(toggled_on: bool) -> void:
	node_mesh.update_overlay_circles(toggled_on)

# when the skeleton button is toggled, we switch between showing the rigid skeleton and the skin mesh
func _on_skeleton_check_button_toggled(toggled_on: bool) -> void:
	node_mesh.update_skeleton_visualization(toggled_on)


func _on_previous_clothing_button_pressed() -> void:
	var texture_label = node_mesh.switch_clothing_texture(-1)
	$PanelContainer/TabBar/Actor/VBoxContainer/ClothesPanel/HBoxContainer/PanelContainer/HBoxContainer/CurrentClothingLabel.text = texture_label


func _on_next_clothing_button_pressed() -> void:
	var texture_label = node_mesh.switch_clothing_texture(1)
	$PanelContainer/TabBar/Actor/VBoxContainer/ClothesPanel/HBoxContainer/PanelContainer/HBoxContainer/CurrentClothingLabel.text = texture_label


func _on_previous_env_button_pressed() -> void:
	var env_label = node_env.switch_environment(-1)
	$PanelContainer/TabBar/Environment/VBoxContainer/EnvPanel/HBoxContainer/PanelContainer/HBoxContainer/CurrentEnvLabel.text = env_label


func _on_next_env_button_pressed() -> void:
	var env_label = node_env.switch_environment(1)
	$PanelContainer/TabBar/Environment/VBoxContainer/EnvPanel/HBoxContainer/PanelContainer/HBoxContainer/CurrentEnvLabel.text = env_label


func _on_previous_effect_button_pressed() -> void:
	var shader_material_label = node_mesh.switch_shader_effect(-1)
	$PanelContainer/TabBar/Actor/VBoxContainer/ShaderPanel/HBoxContainer/PanelContainer/HBoxContainer/CurrentEffectLabel.text = shader_material_label

func _on_next_effect_button_pressed() -> void:
	var shader_material_label = node_mesh.switch_shader_effect(1)
	$PanelContainer/TabBar/Actor/VBoxContainer/ShaderPanel/HBoxContainer/PanelContainer/HBoxContainer/CurrentEffectLabel.text = shader_material_label


func _on_toggle_coordinate_axes_button_toggled(toggled_on: bool) -> void:
	node_env.toggle_coordinate_axes(toggled_on)
