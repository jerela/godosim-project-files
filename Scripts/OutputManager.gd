# Handles storing and writing outputs of the program. In effect, saves images, annotations and labels, and metadata.

extends Node

# tracks how many rows of data (and how many images) are saved
var row_idx: int = 0
# this'll be read from the config file; tells OutputManager how to name files, e.g., if it is defined as 100 in the config file, then first image will be img-0000000101.jpg
var first_image_index: int = 0

# Annotations/labels are added with the append_value() function and pertain to outputs derived from the OpenSim MSK model or spatial dimensions of the visual skin mesh. Examples: generalized coordinate values, joint positions, bounding boxes around the mesh
var labels: Dictionary = {}
# Metadata are related to image conditions, such as camera angle, clothing textures etc.
var metadata: Dictionary = {}
# dictionary to hold file paths that are read from a configuration file
var paths: Dictionary = {}

func _ready() -> void:
	read_config('config.cfg')
	prepare_output_directories()

func read_config(cfg_name: String) -> void:
	# initialize an object to read configuration files
	var config = ConfigFile.new()
	var err = config.load(str("user://Config/", cfg_name))
	if err != OK:
		print('config reading failed')
		return
	paths['output_annotations'] = config.get_value('paths','path_output_annotations')
	paths['output_photos'] = config.get_value('paths','path_output_images_photos')
	paths['output_silhouettes'] = config.get_value('paths','path_output_images_silhouette_masks')
	paths['output_segments'] = config.get_value('paths','path_output_images_segment_masks')
	first_image_index = config.get_value('generate', 'first_image_index')

# Create directories specified as output paths in Config.cfg, if they don't already exist
func prepare_output_directories() -> void:
	for path in paths.values():
		if not DirAccess.dir_exists_absolute(path):
			print('Directory path ', path, ' does not exist, creating directories...')
			var err = DirAccess.make_dir_recursive_absolute(path)
			if err == OK:
				print('... directory path created successfully!')
			else:
				printerr('... something went wrong creating the directory structure! Error code: ', err)
				get_tree().quit()

# append a value to the labels/annotations
func append_value(target_column: String, value: Variant) -> void:
	if labels.has(target_column):
		labels[target_column].append(value)
	else:
		labels[target_column] = []
		labels[target_column].append(value)

# append a value to other metadata
func append_metadata(target_column: String, value: Variant) -> void:
	if metadata.has(target_column):
		metadata[target_column].append(value)
	else:
		metadata[target_column] = []
		metadata[target_column].append(value)

# overwrite a column in metadata
func assign_metadata(target_column: String, arr: Array) -> void:
	metadata[target_column] = arr

# write the labels (joint coordinates, body origin coordinates, bounding box coordinates etc) to file as CSV
func write_coordinate_csv() -> void:
	# if write_coordinate_csv() is called without any screen captures first, we return without writing any files
	if labels.is_empty():
		print("Cannot write annotations because no screen capture have been taken. Use the C key to take screen captures, then press B to write annotations once you're done if you're in demonstration mode.")
		return
	print("Starting to write CSV...")
	var file_path = paths['output_annotations']
	var file_name = "annotations.csv"
	var file_name_full = "/".join([file_path,file_name])
	var save_labels = FileAccess.open(file_name_full, FileAccess.WRITE)
	var column_names = []
	for col in labels.keys():
		column_names.append(col)
	
	save_labels.store_csv_line(PackedStringArray(column_names))
	
	print("Wrote CSV header, now data...")
	for i in range(len(labels['file_names'])):
		var csv_line = parse_row(i,labels)
		
		save_labels.store_csv_line(PackedStringArray(csv_line))
	# close the file once we're done
	save_labels.close()
	print("Saved CSV as: ", file_name_full)


# write to CSV additional data that is not annotations per se, but could be useful information even for training networks
func write_metadata_csv() -> void:
	print("Starting to write CSV...")
	var file_path = paths['output_annotations']
	var file_name = "metadata.csv"
	var file_name_full = "/".join([file_path,file_name])
	var save_labels = FileAccess.open(file_name_full, FileAccess.WRITE)
	var column_names = []
	column_names.append("image_name")
	for col in metadata.keys():
		column_names.append(col)
	
	save_labels.store_csv_line(PackedStringArray(column_names))
	
	print("Wrote CSV header, now data...")
	for i in range(len(labels['file_names'])):
		var csv_line = [labels['file_names'][i]]
		csv_line.append_array(parse_row(i,metadata))
		save_labels.store_csv_line(PackedStringArray(csv_line))
	# close the file once we're done
	save_labels.close()
	print("Saved CSV as: ", file_name_full)

# populate a single line of csv data at row "idx" with values from "data_in"
func parse_row(idx: int, data_in: Dictionary) -> Array:
	var csv_line = []
	# iterate through the number of columns
	for j in range(data_in.size()):
		# if something goes wrong in the next step, this allows us to see it in the output file because some entries will be null
		var string_value = null
		
		# convert different types of values to strings
		var current_value = data_in[data_in.keys()[j]][idx]
		var var_type = typeof(current_value)
		match var_type:
			1: # bool
				string_value = str(int(current_value))
			2: # int
				string_value = str(current_value)
			3: # float
				string_value = str(current_value).pad_decimals(4)
			4: # string
				string_value = str(current_value)
		# add the string-type value to the end of the text line
		csv_line.append(string_value)
	return csv_line

# pretend to save the generated image by doing the relevant operations except for actually saving the image to disk
func mock_save_image(path_str: String, img_name := "") -> void:
	if path_str == 'output_photos':
		row_idx += 1
	var filename = str("img-%010d" % (row_idx+first_image_index))
	var filepath = paths[path_str]
	var filename_full = "/".join([filepath,str(filename,img_name,".jpg")])
	print("Saving screen capture to ", filename_full)
	if path_str == 'output_photos':
		append_value('file_names',filename)

func save_image(img: Image, path_str: String, img_name := "") -> void:
	if path_str == 'output_photos':
		row_idx += 1
	var filename = str("img-%010d" % (row_idx+first_image_index))
	var filepath = paths[path_str]
	var filename_full = "/".join([filepath,str(filename,img_name,".jpg")])
	print("Saving screen capture to ", filename_full)
	img.save_jpg(filename_full)
	if path_str == 'output_photos':
		append_value('file_names',filename)
