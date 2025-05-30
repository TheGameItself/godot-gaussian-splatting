extends Control

# @export variable to hold a reference to the main node
@export var main_node: Node
@export var additional_ply_directory: String = ""

# @onready variables for UI elements
@onready var width_spin_box = $"Panel/VBoxContainer/ResolutionHBox/WidthSpinBox"
@onready var height_spin_box = $"Panel/VBoxContainer/ResolutionHBox/HeightSpinBox"
@onready var frame_time_check_box = $"Panel/VBoxContainer/ResolutionHBox/FrameTimeCheckBox"
@onready var ply_file_option_button = $"Panel/VBoxContainer/PLYFileSelectHBox/PLYFileOptionButton"
@onready var refresh_ply_button = $"Panel/VBoxContainer/PLYFileSelectHBox/RefreshPLYButton"

# Corrected @onready variables for directory selection UI based on .tscn names
@onready var ply_directory_path_label = $"Panel/VBoxContainer/PLYFileSelectHBox/Panel_VBoxContainer_DirectorySelectHBox#PLYDirectoryPathLabel"
@onready var select_directory_button = $"Panel/VBoxContainer/PLYFileSelectHBox/Panel_VBoxContainer_DirectorySelectHBox#SelectDirectoryButton"

# Add @onready variable for the new Load File button
@onready var load_file_button = $"Panel/VBoxContainer/PLYFileSelectHBox/LoadFileButton"

# Add @onready variable for the DirectoryDialog
@onready var directory_dialog = $"Panel/VBoxContainer/DirectoryDialog"

# Called when the node enters the scene tree for the first time.
func _ready():
	# hide() # Removed to make menu visible by default
	
	# Add print statement to check menu.gd _ready execution
	print("menu.gd _ready() called.")
	print("main_node state in menu.gd _ready(): ", main_node)

	# Connect signals that DO NOT require main_node to be set
	if !Engine.is_editor_hint():
		# Connect signals within the menu script regardless of main_node
		width_spin_box.value_changed.connect(_on_resolution_spinbox_value_changed)
		height_spin_box.value_changed.connect(_on_resolution_spinbox_value_changed)
		frame_time_check_box.toggled.connect(_on_frame_time_check_box_toggled)

		# Connect PLY file selection and directory signals (independent of main_node)
		if select_directory_button != null:
			select_directory_button.pressed.connect(_on_select_directory_button_pressed)

		# Connect the item_selected signal, but it will no longer trigger file loading directly
		ply_file_option_button.item_selected.connect(_on_ply_file_option_button_item_selected)

		# Populate the list of PLY files when the menu is ready (only run in game)
		_populate_ply_files()

		# Re-add signal connection for RefreshPLYButton
		if refresh_ply_button != null:
			refresh_ply_button.pressed.connect(_on_refresh_ply_button_pressed)

		# Defer connecting signal for the new Load File button to ensure main_node is set
		if load_file_button != null:
			load_file_button.pressed.connect(_on_load_file_button_pressed, CONNECT_DEFERRED)

		# Connect DirectoryDialog signal
		if directory_dialog != null:
			directory_dialog.dir_selected.connect(_on_directory_dialog_dir_selected)

# New function to initialize the menu with the main node reference and connect dependent signals
func initialize_menu(main_node_ref: Node):
	# Add print statement to confirm initialize_menu is called
	print("menu.gd initialize_menu() called.")
	main_node = main_node_ref
	print("main_node set in initialize_menu(): ", main_node)
	
	# Connect signals that DO require main_node to be set
	if main_node:
		width_spin_box.value_changed.connect(main_node._on_menu_resolution_changed)
		height_spin_box.value_changed.connect(main_node._on_menu_resolution_changed)
		frame_time_check_box.toggled.connect(main_node._on_menu_frame_time_toggled)
		print("Resolution and frametime signals connected to main_node.")
	else:
		print("Error: main_node is null in initialize_menu(). Dependent signals not connected.")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	# Logic to run only in the editor
	if Engine.is_editor_hint():
		# Update the directory path label
		if additional_ply_directory != "":
			ply_directory_path_label.text = additional_ply_directory
		else:
			ply_directory_path_label.text = "No directory selected"
		
		# Populate the OptionButton with placeholder items if empty
		if ply_file_option_button != null and ply_file_option_button.get_item_count() == 0:
			ply_file_option_button.add_item("placeholder_file_1.ply")
			ply_file_option_button.add_item("placeholder_file_2.ply")
			ply_file_option_button.add_item("placeholder_file_3.ply")

# Function to toggle the menu's visibility
func toggle_visibility():
	visible = !visible
	if visible:
		_on_menu_opened()

# Function to update menu elements when the menu is opened
func _on_menu_opened():
	if main_node:
		var viewport_size = main_node.get_viewport().size
		width_spin_box.value = viewport_size.x
		height_spin_box.value = viewport_size.y

# Placeholder functions for signal handling
func _on_resolution_spinbox_value_changed(_value):
	# This function is still needed to handle the signal within the menu if necessary,
	# but the main logic will be in main_node._on_menu_resolution_changed.
	# TODO: Potentially update a label showing the current resolution here
	pass

func _on_frame_time_check_box_toggled(_button_pressed):
	# This function is still needed to handle the signal within the menu if necessary,
	# but the main logic will be in main_node._on_menu_frame_time_toggled.
	pass

# Recursive helper function to scan directories for .ply files
func _scan_directory_recursive(path, ply_files_list):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				if dir.current_is_dir():
					# If it's a directory, recurse into it
					_scan_directory_recursive(path + "/" + file_name, ply_files_list)
				elif file_name.ends_with(".ply"):
					# If it's a .ply file, add its full path to the list
					ply_files_list.append(path + "/" + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		print("Could not open directory for recursive scan: ", path)

# Scans specified directories for .ply files and populates the OptionButton.
func _populate_ply_files():
	ply_file_option_button.clear()
	var ply_files = []
	
	# Scan res:// directory recursively
	_scan_directory_recursive("res://", ply_files)

	# Scan additional user-specified directory recursively if set
	if additional_ply_directory != "":
		_scan_directory_recursive(additional_ply_directory, ply_files)

	# Populate OptionButton with found files
	for file_path in ply_files:
		ply_file_option_button.add_item(file_path)

# Called when an item is selected in the OptionButton
func _on_ply_file_option_button_item_selected(index):
	var selected_path = ply_file_option_button.get_item_text(index)
	print("Selected PLY file: ", selected_path)
	# The file loading is now triggered by the Load File button, not selecting an item here.

# Called when the Refresh button is pressed.
func _on_refresh_ply_button_pressed():
	print("Refresh button pressed.")
	_populate_ply_files()
	print("PLY file list refreshed.")

# Called when the Select Directory button is pressed.
func _on_select_directory_button_pressed():
	print("Select Directory button pressed.")
	# Calculate dialog size based on viewport and requested margins
	var viewport_size = get_viewport().size
	var margin_left = 20
	var margin_right = 20
	var margin_top = 20
	var margin_bottom = 50
	
	var dialog_width = max(100, viewport_size.x - margin_left - margin_right) # Ensure min width
	var dialog_height = max(100, viewport_size.y - margin_top - margin_bottom) # Ensure min height
	
	var dialog_size = Vector2(dialog_width, dialog_height)

	# Open the DirectoryDialog with calculated size
	if directory_dialog != null:
		directory_dialog.size = dialog_size
		directory_dialog.popup_centered()
	print("Select Directory button pressed. Attempting to open dialog with size:", dialog_size)

# Called when the new Load File button is pressed.
func _on_load_file_button_pressed():
	print("Load File button pressed.")
	var selected_file_path = ply_file_option_button.get_item_text(ply_file_option_button.get_selected_id())
	print("Attempting to load file: ", selected_file_path)
	
	# Add a check to ensure main_node is set before attempting to load
	if !main_node:
		print("Error: main_node is not set in menu.gd. Cannot load new file.")
		return # Exit the function if main_node is null
	
	# Update the splat_filename in the main node instance
	main_node.splat_filename = selected_file_path
	
	# Instead of reloading the scene, call the main node's load function
	main_node._load_ply_file(selected_file_path)
	
	print("Requested main node to load new splat_filename: ", selected_file_path)
	hide() # Hide the menu after loading the file

# Called when a directory is selected in the DirectoryDialog.
func _on_directory_dialog_dir_selected(dir_path):
	additional_ply_directory = dir_path
	ply_directory_path_label.text = dir_path
	_populate_ply_files() # Refresh the PLY file list
	print("Directory selected: ", dir_path)
