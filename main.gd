# TODO: Always try to apply changes when possible. If not possible, try anyway and document the result.
# Reminder: After any code change, test and document it.

print("[DEBUG] Development loop: change applied at top of main.gd")

extends Node3D

@onready var camera = get_node("Camera")
@onready var screen_texture = get_node("TextureRect")
@export var splat_filename: String = r"C:\Users\basti\Documents\GodotProjects\godot-gaussian-splatting-main\Testing Data\3DGS_PLY_sample_data\PLY(postshot)\cactus_splat3_30kSteps_719k_splats.ply"

var rd = RenderingServer.get_rendering_device()
var pipeline: RID
var shader: RID
var vertex_format: int
var blend := RDPipelineColorBlendState.new()

var framebuffer: RID
var vertex_array: RID
var index_array: RID
var static_uniform_set: RID
var dynamic_uniform_set: RID
var clear_color_values := PackedColorArray([Color(1,0,1,1)]) # Experiment: magenta clear color for debug, revert if needed

var cull_uniform_set1: RID
var cull_uniform_set2: RID

var num_coeffs = 45
var num_coeffs_per_color = num_coeffs / 3
var sh_degree = sqrt(num_coeffs_per_color + 1) - 1	

var sort_pipeline: RID
var histogram_pipeline: RID
var depth_out_buffer: RID
var histogram_buffer: RID
var depth_uniform
var depth_out_uniform
var histogram_uniform_set0
var histogram_uniform_set1
var radixsort_hist_shader: RID
var radixsort_shader: RID
var globalInvocationSize: int

var cull_buffer: RID
var cull_uniform: RDUniform
var visible_counter_buffer: RID
var visible_counter_uniform: RDUniform
var cull_pipeline: RID
var cull_shader: RID

var visible_count: int = 0

var num_vertex: int
var output_tex: RID

var display_texture:Texture2DRD

var camera_matrices_buffer: RID
var params_buffer: RID
var modifier: float = 1.0
var last_direction := Vector3.ZERO
var last_position := Vector3.ZERO

var vertices: PackedFloat32Array

const NUM_BLOCKS_PER_WORKGROUP = 1024
var NUM_WORKGROUPS

var log_file_path := "run_log.txt"
var log_file: FileAccess = null

var last_frame_log_time := 0
var frame_count := 0
var last_fps_log_time := 0

func log_event(event: String):
	var timestamp = Time.get_ticks_msec()
	if log_file == null:
		log_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	log_file.store_line("[%s ms] %s" % [timestamp, event])
	log_file.flush()

func _matrix_to_bytes(t : Transform3D):
	var basis : Basis = t.basis
	var origin : Vector3 = t.origin
	var bytes : PackedByteArray = PackedFloat32Array([
		basis.x.x, basis.x.y, basis.x.z, 0.0,
		basis.y.x, basis.y.y, basis.y.z, 0.0,
		basis.z.x, basis.z.y, basis.z.z, 0.0,
		origin.x, origin.y, origin.z, 1.0
	]).to_byte_array()
	return bytes


func _initialise_screen_texture():
	display_texture = Texture2DRD.new()
	screen_texture.texture = display_texture


func _load_ply_file():
	var file = FileAccess.open(splat_filename, FileAccess.READ)

	if not file:
		print("Failed to open file: " + splat_filename)
		log_error("Failed to open file: %s" % splat_filename)
		return

	var num_properties = 0
	var line = file.get_line()
	while not file.eof_reached():
		if line.begins_with("element vertex"):
			num_vertex = int(line.split(" ")[2])
		elif line.begins_with("property"):
			num_properties += 1
		elif line.begins_with("end_header"):
			break
		line = file.get_line()
	
	print("num splats: ", num_vertex)
	print("num properties: ", num_properties)
	
	vertices = file.get_buffer(num_vertex * num_properties * 4).to_float32_array()
	file.close()
	print("First 10 vertex values: ", vertices.slice(0, 10))
	

func _initialise_framebuffer_format():
	_initialise_screen_texture()
	var tex_format := RDTextureFormat.new()
	var tex_view := RDTextureView.new()
	tex_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tex_format.height = get_viewport().size.y
	tex_format.width = get_viewport().size.x
	tex_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tex_format.usage_bits = (RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT)
	output_tex = rd.texture_create(tex_format,tex_view)

	display_texture.texture_rd_rid = output_tex
	
	var attachments = []
	var attachment_format := RDAttachmentFormat.new()
	attachment_format.set_format(tex_format.format)
	attachment_format.set_samples(RenderingDevice.TEXTURE_SAMPLES_1)
	attachment_format.usage_flags = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	attachments.push_back(attachment_format)	
	var framebuf_format = rd.framebuffer_format_create(attachments)
	return framebuf_format


# Called when the node enters the scene tree for the first time.
func _ready():
	print("[DEBUG] _ready() called")
	log_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	log_event("Startup: _ready() called")
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	print("[DEBUG] Unpacking .ply file data...")
	log_event("Begin loading PLY file: %s" % splat_filename)
	_load_ply_file()
	print("[DEBUG] Loaded vertices count: ", vertices.size())
	
	print("[DEBUG] Configuring shaders and buffers...")
	log_event("Configuring shaders and buffers")
	var vertices_buffer = rd.storage_buffer_create(vertices.size() * 4, vertices.to_byte_array())
	print("vertices_buffer RID: ", vertices_buffer, " size: ", vertices.size() * 4)
	log_event("Created vertices buffer")
	
	var vertices_uniform = RDUniform.new()
	vertices_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	vertices_uniform.binding = 0
	vertices_uniform.add_id(vertices_buffer)
	
	var tan_fovy = tan(deg_to_rad($Camera.fov) * 0.5)
	var tan_fovx = tan_fovy * get_viewport().size.x / get_viewport().size.y
	var focal_y = get_viewport().size.y / (2 * tan_fovy)
	var focal_x = get_viewport().size.x / (2 * tan_fovx)
	
	# Viewport size buffer
	var params : PackedByteArray = PackedFloat32Array([
		get_viewport().size.x,
		get_viewport().size.y,
		tan_fovx,
		tan_fovy,
		focal_x,
		focal_y,
		modifier,
		sh_degree,
	]).to_byte_array()
	params_buffer = rd.storage_buffer_create(params.size(), params)
	print("params_buffer RID: ", params_buffer, " size: ", params.size())
	var params_uniform := RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	params_uniform.binding = 1
	params_uniform.add_id(params_buffer)
		
	var radixsort_shader_file = load("res://shaders/multi_radixsort.glsl")
	var radixsort_shader_spirv = radixsort_shader_file.get_spirv()
	radixsort_shader = rd.shader_create_from_spirv(radixsort_shader_spirv)

	var radixsort_hist_shader_file = load("res://shaders/multi_radixsort_histograms.glsl")
	var radisxsort_hist_spirv = radixsort_hist_shader_file.get_spirv()
	radixsort_hist_shader = rd.shader_create_from_spirv(radisxsort_hist_spirv)
	
	globalInvocationSize = num_vertex / NUM_BLOCKS_PER_WORKGROUP
	var remainder = num_vertex % NUM_BLOCKS_PER_WORKGROUP
	if remainder > 0:
		globalInvocationSize += 1

	var WORKGROUP_SIZE = 512
	var RADIX_SORT_BINS = 256
	NUM_WORKGROUPS = num_vertex / WORKGROUP_SIZE

	
	var depth_out_data = PackedInt32Array()
	var hist_data = PackedInt32Array()
		
	depth_out_data.resize(num_vertex * 2)
	hist_data.resize(RADIX_SORT_BINS * NUM_WORKGROUPS)
	

	depth_out_buffer = rd.storage_buffer_create(depth_out_data.size() * 4, depth_out_data.to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	histogram_buffer = rd.storage_buffer_create(hist_data.size() * 4, hist_data.to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	
	depth_out_uniform = RDUniform.new()
	depth_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	depth_out_uniform.binding = 1
	depth_out_uniform.add_id(depth_out_buffer)
	
	histogram_uniform_set0 = RDUniform.new()
	histogram_uniform_set0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	histogram_uniform_set0.binding = 1
	histogram_uniform_set0.add_id(histogram_buffer)	
	
	histogram_uniform_set1 = RDUniform.new()
	histogram_uniform_set1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	histogram_uniform_set1.binding = 2
	histogram_uniform_set1.add_id(histogram_buffer)	
	
	sort_pipeline = rd.compute_pipeline_create(radixsort_shader)
	histogram_pipeline = rd.compute_pipeline_create(radixsort_hist_shader)

	# Configure splat vertex/frag shader
	var shader_file = load("res://shaders/splat.glsl")
	var shader_spirv = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)

	var points := PackedFloat32Array([
		-1,-1,0,
		1,-1,0,
		-1,1,0,
		1,1,0,
	])
	var points_bytes := points.to_byte_array()
	
	var indices := PackedByteArray()
	indices.resize(12)
	var pos = 0
	
	for i in [0,2,1,0,2,3]:
		indices.encode_u16(pos,i)
		pos += 2
		
	var index_buffer = rd.index_buffer_create(6,RenderingDevice.INDEX_BUFFER_FORMAT_UINT16,indices)
	index_array = rd.index_array_create(index_buffer,0,6)
	
	var vertex_buffers := [
		rd.vertex_buffer_create(points_bytes.size(), points_bytes),
	]
	
	var vertex_attrs = [ RDVertexAttribute.new()]
	vertex_attrs[0].format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	vertex_attrs[0].location = 0
	vertex_attrs[0].stride = 4 * 3
	vertex_format = rd.vertex_format_create(vertex_attrs)
	vertex_array = rd.vertex_array_create(4, vertex_format, vertex_buffers)
			
	# Camera Matrices Buffer
	var cam_to_world : Transform3D = camera.global_transform
	var camera_matrices_bytes := PackedByteArray()
	camera_matrices_bytes.append_array(_matrix_to_bytes(cam_to_world))
	camera_matrices_bytes.append_array(PackedFloat32Array([4000.0, 0.05]).to_byte_array())
	camera_matrices_buffer = rd.storage_buffer_create(camera_matrices_bytes.size(), camera_matrices_bytes)
	var camera_matrices_uniform := RDUniform.new()
	camera_matrices_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	camera_matrices_uniform.binding = 3
	camera_matrices_uniform.add_id(camera_matrices_buffer)
	
	
	# Configure blend mode
	var blend_attachment = RDPipelineColorBlendStateAttachment.new()	
	blend_attachment.enable_blend = true
	blend_attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	blend_attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	blend_attachment.color_blend_op = RenderingDevice.BLEND_OP_ADD
	blend_attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	blend_attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	blend_attachment.alpha_blend_op = RenderingDevice.BLEND_OP_ADD
	blend_attachment.write_r = true
	blend_attachment.write_g = true
	blend_attachment.write_b = true
	blend_attachment.write_a = true 
	blend.attachments.push_back(blend_attachment)	

	var framebuffer_format = _initialise_framebuffer_format()
	framebuffer = rd.framebuffer_create([output_tex], framebuffer_format)
	print("[DEBUG] framebuffer valid: ",rd.framebuffer_is_valid(framebuffer))
	

	cull_buffer = rd.storage_buffer_create(num_vertex * 2 * 4)
	cull_uniform = RDUniform.new()
	cull_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	cull_uniform.binding = 4
	cull_uniform.add_id(cull_buffer)
	
	depth_uniform = RDUniform.new()
	depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	depth_uniform.binding = 0
	depth_uniform.add_id(cull_buffer)
		
	
	# Counter buffer (only one uint)
	var zero = PackedByteArray()
	zero.resize(4)
	visible_counter_buffer = rd.storage_buffer_create(4, zero)
	visible_counter_uniform = RDUniform.new()
	visible_counter_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	visible_counter_uniform.binding = 2
	visible_counter_uniform.add_id(visible_counter_buffer)
	
	# Load and create pipeline
	var cull_shader_file = load("res://shaders/visible_splats.glsl")
	var cull_shader_spirv = cull_shader_file.get_spirv()
	cull_shader = rd.shader_create_from_spirv(cull_shader_spirv)
	cull_pipeline = rd.compute_pipeline_create(cull_shader)
	
	
	var static_bindings = [
		vertices_uniform,
	]
	
	var dynamic_bindings = [
		camera_matrices_uniform,
		params_uniform,
		cull_uniform,
	]
	
	dynamic_uniform_set = rd.uniform_set_create(dynamic_bindings, shader, 0)
	static_uniform_set = rd.uniform_set_create(static_bindings, shader, 1)
	
	pipeline = rd.render_pipeline_create(
		shader,
		framebuffer_format,
		vertex_format,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLE_STRIPS,
		RDPipelineRasterizationState.new(),
		RDPipelineMultisampleState.new(),
		RDPipelineDepthStencilState.new(),
		blend
	)
	
	var cull_bindings = [
		params_uniform,
		visible_counter_uniform,
		camera_matrices_uniform,
		cull_uniform,  # output = compacted_buffer
	]

	cull_uniform_set1 = rd.uniform_set_create(cull_bindings, cull_shader, 0)
	cull_uniform_set2 = rd.uniform_set_create(static_bindings, cull_shader, 1)
	
	
	print("[DEBUG] render pipeline valid: ", rd.render_pipeline_is_valid(pipeline))
	print("[DEBUG] compute1 pipeline valid: ", rd.compute_pipeline_is_valid(sort_pipeline))
	print("[DEBUG] visible compute pipeline valid: ", rd.compute_pipeline_is_valid(cull_pipeline))
	print("[DEBUG] Calling update, render, compute_depth_and_visibility, radix_sort...")
	update()
	render()
	compute_depth_and_visibility()
	radix_sort()


func compute_depth_and_visibility():
	# Reset visible counter
	visible_count = 0
	var zero := PackedByteArray([0, 0, 0, 0])
	rd.buffer_update(visible_counter_buffer, 0, 4, zero)
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, cull_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, cull_uniform_set1, 0)
	rd.compute_list_bind_uniform_set(compute_list, cull_uniform_set2, 1)
	var num_groups = int(ceil(float(num_vertex) / 512.0))
	rd.compute_list_dispatch(compute_list, num_groups, 1, 1)
	rd.compute_list_end()
	
	var visible_count = rd.buffer_get_data(visible_counter_buffer).to_int32_array()[0]
	print(visible_count)


# Reconfigure render pipeline with new viewport size
func _on_viewport_size_changed():
	var framebuf_format = _initialise_framebuffer_format()
	framebuffer = rd.framebuffer_create([output_tex], framebuf_format)
	
	pipeline = rd.render_pipeline_create(
		shader,
		framebuf_format,
		vertex_format,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLE_STRIPS,
		RDPipelineRasterizationState.new(),
		RDPipelineMultisampleState.new(),
		RDPipelineDepthStencilState.new(),
		blend
	)

	
func radix_sort():
	# Read visible count
	visible_count = rd.buffer_get_data(visible_counter_buffer).to_int32_array()[0]
	
	globalInvocationSize = visible_count / NUM_BLOCKS_PER_WORKGROUP
	var remainder = visible_count % NUM_BLOCKS_PER_WORKGROUP
	if remainder > 0:
		globalInvocationSize += 1
	
	# Skip sort if nothing visible
	if visible_count == 0:
		return

	var compute_list := rd.compute_list_begin()
	for i in range(4):
		var push_constant = PackedInt32Array([visible_count, i * 8, NUM_WORKGROUPS, NUM_BLOCKS_PER_WORKGROUP])

		depth_uniform.clear_ids()
		depth_out_uniform.clear_ids()

		# Use compacted buffer as input
		if i == 0 or i == 2:
			depth_uniform.add_id(cull_buffer)
			depth_out_uniform.add_id(depth_out_buffer)
		else:
			depth_uniform.add_id(depth_out_buffer)
			depth_out_uniform.add_id(cull_buffer)

		# Histogram and sort stages (same as before)
		var histogram_bindings = [
			depth_uniform,
			histogram_uniform_set0
		]
		var hist_uniform_set = rd.uniform_set_create(histogram_bindings, radixsort_hist_shader, 0)

		rd.compute_list_bind_compute_pipeline(compute_list, histogram_pipeline)
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
		rd.compute_list_bind_uniform_set(compute_list, hist_uniform_set, 0)
		rd.compute_list_dispatch(compute_list, globalInvocationSize, 1, 1)
		rd.compute_list_add_barrier(compute_list)

		var radixsort_bindings = [
			depth_uniform,
			depth_out_uniform,
			histogram_uniform_set1
		]
		var sort_uniform_set = rd.uniform_set_create(radixsort_bindings, radixsort_shader, 1)

		rd.compute_list_bind_compute_pipeline(compute_list, sort_pipeline)
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
		rd.compute_list_bind_uniform_set(compute_list, sort_uniform_set, 1)
		rd.compute_list_dispatch(compute_list, globalInvocationSize, 1, 1)
		rd.compute_list_add_barrier(compute_list)

	rd.compute_list_end()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func update():
	print("[DEBUG] update() called")
	# Camera Matrices Buffer
	var camera_matrices_bytes := PackedByteArray()
	camera_matrices_bytes.append_array(_matrix_to_bytes(camera.global_transform.affine_inverse()))
	camera_matrices_bytes.append_array(PackedFloat32Array([4000.0, 0.05]).to_byte_array())
	rd.buffer_update(camera_matrices_buffer, 0, camera_matrices_bytes.size(), camera_matrices_bytes)

	var tan_fovy = tan(deg_to_rad($Camera.fov) * 0.5)
	var tan_fovx = tan_fovy * get_viewport().size.x / get_viewport().size.y
	var focal_y = get_viewport().size.y / (2 * tan_fovy)
	var focal_x = get_viewport().size.x / (2 * tan_fovx)

	# Viewport size buffer
	var params : PackedByteArray = PackedFloat32Array([
		get_viewport().size.x,
		get_viewport().size.y,
		tan_fovx,
		tan_fovy,
		focal_x,
		focal_y,
		modifier,
		sh_degree,
	]).to_byte_array()
	rd.buffer_update(params_buffer, 0, params.size(), params)
	print("[DEBUG] update() - viewport size: ", get_viewport().size, " modifier: ", modifier, " sh_degree: ", sh_degree)
	_sort_splats_by_depth()
	

func render():
	print("[DEBUG] render() called. visible_count: ", visible_count)
	# Use integer values for initial/final actions if enums are not available in this Godot version
	var draw_list := rd.draw_list_begin(
		framebuffer,
		RenderingDevice.INITIAL_ACTION_CLEAR if "INITIAL_ACTION_CLEAR" in RenderingDevice else 1, # initial color action: Clear
		RenderingDevice.FINAL_ACTION_STORE if "FINAL_ACTION_STORE" in RenderingDevice else 3,     # final color action: Store
		RenderingDevice.INITIAL_ACTION_CLEAR if "INITIAL_ACTION_CLEAR" in RenderingDevice else 1, # initial depth action: Clear
		RenderingDevice.FINAL_ACTION_STORE if "FINAL_ACTION_STORE" in RenderingDevice else 3,     # final depth action: Store
		clear_color_values
	)
	print("[DEBUG] Binding render pipeline and uniforms...")
	rd.draw_list_bind_render_pipeline(draw_list, pipeline)
	rd.draw_list_bind_uniform_set(draw_list, dynamic_uniform_set, 0)
	rd.draw_list_bind_uniform_set(draw_list, static_uniform_set, 1)
	rd.draw_list_bind_vertex_array(draw_list, vertex_array)
	print("[DEBUG] Drawing with visible_count: ", visible_count)
	rd.draw_list_draw(draw_list, false, visible_count)
	rd.draw_list_end()

func _process(delta):	
	update()
	render()
	frame_count += 1
	var now = Time.get_ticks_msec()
	if now - last_frame_log_time > 1000:
		log_event("Frame time: %s ms, FPS: %s" % [str(delta * 1000.0), str(frame_count)])
		last_frame_log_time = now
		frame_count = 0
	
	
func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			modifier += 0.05
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			modifier -= 0.05
		

func _sort_splats_by_depth():
	var new_position = camera.global_transform.origin
	var new_direction = camera.global_transform.basis.z.normalized()

	var direction_delta = last_direction.dot(new_direction)
	var angle_change = acos(clamp(direction_delta, -1, 1))

	var position_delta = new_position.distance_to(last_position)

	if angle_change > 0.05 or position_delta > 0.05:
		compute_depth_and_visibility()
		radix_sort()
		last_direction = new_direction
		last_position = new_position

		

func log_error(msg: String):
	log_event("ERROR: %s" % msg)

		
