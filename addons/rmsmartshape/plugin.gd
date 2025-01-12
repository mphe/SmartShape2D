@tool
extends EditorPlugin


## Common Abbreviations
## et = editor transform (viewport's canvas transform)
##
## - Snapping using the build in functionality isn't going to happen
## 	- https://github.com/godotengine/godot/issues/11180
## 	- https://godotengine.org/qa/18051/tool-script-in-3-0

# Icons
# TODO: Change to const and preload when this is resolved:
# https://github.com/godotengine/godot/issues/17483
var ICON_HANDLE: Texture2D = load("res://addons/rmsmartshape/assets/icon_editor_handle.svg")
var ICON_HANDLE_SELECTED: Texture2D = load("res://addons/rmsmartshape/assets/icon_editor_handle_selected.svg")
var ICON_HANDLE_BEZIER: Texture2D = load("res://addons/rmsmartshape/assets/icon_editor_handle_bezier.svg")
var ICON_HANDLE_CONTROL: Texture2D = load("res://addons/rmsmartshape/assets/icon_editor_handle_control.svg")
var ICON_FREEHAND_MODE: Texture2D = load("res://addons/rmsmartshape/assets/freehand.png")
var ICON_CIRCLE_ERASE: Texture2D = load("res://addons/rmsmartshape/assets/icon_editor_snap.svg")
var ICON_ADD_HANDLE: Texture2D = load("res://addons/rmsmartshape/assets/icon_editor_handle_add.svg")
var ICON_CURVE_EDIT: Texture2D = load("res://addons/rmsmartshape/assets/icon_curve_edit.svg")
var ICON_CURVE_CREATE: Texture2D = load("res://addons/rmsmartshape/assets/icon_curve_create.svg")
var ICON_CURVE_DELETE: Texture2D = load("res://addons/rmsmartshape/assets/icon_curve_delete.svg")
var ICON_PIVOT_POINT: Texture2D = load("res://addons/rmsmartshape/assets/icon_editor_position.svg")
var ICON_COLLISION: Texture2D = load("res://addons/rmsmartshape/assets/icon_collision_polygon_2d.svg")
var ICON_INTERP_LINEAR: Texture2D = load("res://addons/rmsmartshape/assets/InterpLinear.svg")
var ICON_SNAP: Texture2D = load("res://addons/rmsmartshape/assets/icon_editor_snap.svg")
var ICON_IMPORT_CLOSED: Texture2D = load("res://addons/rmsmartshape/assets/closed_shape.png")
var ICON_IMPORT_OPEN: Texture2D = load("res://addons/rmsmartshape/assets/open_shape.png")

const FUNC = preload("plugin-functionality.gd")

enum MODE { EDIT_VERT, EDIT_EDGE, SET_PIVOT, CREATE_VERT, FREEHAND }

enum ACTION_VERT {
	NONE = 0,
	MOVE_VERT = 1,
	MOVE_CONTROL = 2,
	MOVE_CONTROL_IN = 3,
	MOVE_CONTROL_OUT = 4,
	MOVE_WIDTH_HANDLE = 5
}


# Data related to an action being taken on points
class ActionDataVert:
	#Type of Action from the ACTION_VERT enum
	var type: ACTION_VERT = ACTION_VERT.NONE
	# The affected Verticies and their initial positions
	var keys: Array[int] = []
	var starting_width: Array[float] = []
	var starting_positions: PackedVector2Array = []
	var starting_positions_control_in: PackedVector2Array = []
	var starting_positions_control_out: PackedVector2Array = []

	func _init(
		_keys: Array[int],
		positions: PackedVector2Array,
		positions_in: PackedVector2Array,
		positions_out: PackedVector2Array,
		width: Array[float],
		t: ACTION_VERT
	):
		type = t
		keys = _keys
		starting_positions = positions
		starting_positions_control_in = positions_in
		starting_positions_control_out = positions_out
		starting_width = width

	func are_verts_selected() -> bool:
		return keys.size() > 0

	func _to_string() -> String:
		var s := "%s: %s = %s"
		return s % [type, keys, starting_positions]

	func is_single_vert_selected() -> bool:
		if keys.size() == 1:
			return true
		return false

	func current_point_key() -> int:
		if not is_single_vert_selected():
			return -1
		return keys[0]

	func current_point_index(s: SS2D_Shape_Base) -> int:
		if not is_single_vert_selected():
			return -1
		return s.get_point_index(keys[0])


# PRELOADS
var GUI_SNAP_POPUP = preload("scenes/SnapPopup.tscn")
var GUI_POINT_INFO_PANEL = preload("scenes/GUI_InfoPanel.tscn")
var GUI_EDGE_INFO_PANEL = preload("scenes/GUI_Edge_InfoPanel.tscn")
var gui_point_info_panel = GUI_POINT_INFO_PANEL.instantiate()
var gui_edge_info_panel = GUI_EDGE_INFO_PANEL.instantiate()
var gui_snap_settings = GUI_SNAP_POPUP.instantiate()

const GUI_POINT_INFO_PANEL_OFFSET := Vector2(256, 130)

# This is the shape node being edited
var shape: SS2D_Shape_Base = null

# Toolbar Stuff
var tb_hb: HBoxContainer = null
var tb_vert_create: Button = null
var tb_vert_edit: Button = null
var tb_edge_edit: Button = null
var tb_pivot: Button = null
var tb_collision: Button = null
var tb_freehand: Button = null
var tb_button_group: ButtonGroup = null

var tb_snap: MenuButton = null
# The PopupMenu that belongs to tb_snap
var tb_snap_popup: PopupMenu = null

# Edge Stuff
var on_edge: bool = false
var edge_point: Vector2
var edge_data: SS2D_Edge = null

# Width Handle Stuff
var on_width_handle: bool = false
const WIDTH_HANDLE_OFFSET: float = 60.0
var closest_key: int
var closest_edge_keys: Array[int] = [-1, -1]
var width_scaling: float

# Vertex paint mode stuff
var last_point_position: Vector2
var _mouse_lmb_pressed := false
var _mouse_rmb_pressed := false
var freehand_paint_size := 20.0
var freehand_erase_size := 40.0

# Track our mode of operation
var current_mode: int = MODE.CREATE_VERT
var previous_mode: int = MODE.CREATE_VERT

var current_action := ActionDataVert.new([], [], [], [], [], ACTION_VERT.NONE)
var cached_shape_global_transform: Transform2D

# Action Move Variables
var _mouse_motion_delta_starting_pos := Vector2(0, 0)

# Defining the viewport to get the current zoom/scale
var target_viewport: Viewport
var current_zoom_level : float = 1.0

# Track the property plugin
var plugin: EditorInspectorPlugin

var is_2d_screen_active := false

#######
# GUI #
#######


func gui_display_snap_settings() -> void:
	var pos := tb_snap.get_screen_position() + tb_snap.size
	pos.x -= (gui_snap_settings.size.x + tb_snap.size.x) / 2.0
	gui_snap_settings.position = pos
	gui_snap_settings.popup()


func _snapping_item_selected(id: int) -> void:
	if id == 0:
		tb_snap_popup.set_item_checked(id, not tb_snap_popup.is_item_checked(id))
	if id == 1:
		tb_snap_popup.set_item_checked(id, not tb_snap_popup.is_item_checked(id))
	elif id == 3:
		gui_display_snap_settings()


func _gui_build_toolbar() -> void:
	tb_hb = HBoxContainer.new()
	add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, tb_hb)

	var sep := VSeparator.new()
	tb_hb.add_child(sep)

	tb_button_group = ButtonGroup.new()

	tb_vert_create = create_tool_button(ICON_CURVE_CREATE, SS2D_Strings.EN_TOOLTIP_CREATE_VERT)
	tb_vert_create.connect("pressed", self._enter_mode.bind(MODE.CREATE_VERT))
	tb_vert_create.button_pressed = true

	tb_vert_edit = create_tool_button(ICON_CURVE_EDIT, SS2D_Strings.EN_TOOLTIP_EDIT_VERT)
	tb_vert_edit.connect("pressed", self._enter_mode.bind(MODE.EDIT_VERT))

	tb_edge_edit = create_tool_button(ICON_INTERP_LINEAR, SS2D_Strings.EN_TOOLTIP_EDIT_EDGE)
	tb_edge_edit.connect("pressed", self._enter_mode.bind(MODE.EDIT_EDGE))

	tb_pivot = create_tool_button(ICON_PIVOT_POINT, SS2D_Strings.EN_TOOLTIP_EDIT_VERT)
	tb_pivot.connect("pressed", self._enter_mode.bind(MODE.SET_PIVOT))

	tb_freehand = create_tool_button(ICON_FREEHAND_MODE, SS2D_Strings.EN_TOOLTIP_FREEHAND)
	tb_freehand.connect("pressed", self._enter_mode.bind(MODE.FREEHAND))

	tb_collision = create_tool_button(ICON_COLLISION, SS2D_Strings.EN_TOOLTIP_COLLISION)
	tb_collision.connect("pressed", self._add_collision)


	tb_snap = MenuButton.new()
	tb_snap.tooltip_text = SS2D_Strings.EN_TOOLTIP_SNAP
	tb_snap_popup = tb_snap.get_popup()
	tb_snap.icon = ICON_SNAP
	tb_snap_popup.add_check_item("Use Grid Snap")
	tb_snap_popup.add_check_item("Snap Relative")
	tb_snap_popup.add_separator()
	tb_snap_popup.add_item("Configure Snap...")
	tb_snap_popup.hide_on_checkable_item_selection = false
	tb_hb.add_child(tb_snap)
	tb_snap_popup.connect("id_pressed", self._snapping_item_selected)

	tb_hb.hide()


func create_tool_button(icon: Texture2D, tooltip: String) -> Button:
	var tb := Button.new()
	tb.toggle_mode = true
	tb.button_group =  tb_button_group
	tb.focus_mode = Control.FOCUS_NONE
	tb.flat = true
	tb.icon = icon
	tb.tooltip_text = tooltip
	tb_hb.add_child(tb)
	return tb


func _gui_update_vert_info_panel() -> void:
	var idx: int = current_action.current_point_index(shape)
	var key: int = current_action.current_point_key()
	if not is_key_valid(shape, key):
		gui_point_info_panel.visible = false
		return
	gui_point_info_panel.visible = true
	# Shrink panel
	gui_point_info_panel.size = Vector2(1, 1)

	var properties := shape.get_point_properties(key)
	gui_point_info_panel.set_idx(idx)
	gui_point_info_panel.set_texture_idx(properties.texture_idx)
	gui_point_info_panel.set_width(properties.width)
	gui_point_info_panel.set_flip(properties.flip)


func _process(_delta: float) -> void:
	if current_mode == MODE.FREEHAND:
		current_zoom_level = get_canvas_scale()


func get_canvas_scale() -> float:
	get_current_viewport()
	if target_viewport:
		return target_viewport.global_canvas_transform.x.x
	else:
		return 1.0


func get_current_viewport() -> void:
	if !get_tree().get_edited_scene_root():
		return
	var editor_viewport: Node = get_tree().get_edited_scene_root().get_parent()

	if editor_viewport is SubViewport:
		target_viewport = editor_viewport
	elif editor_viewport is SubViewportContainer:
		target_viewport = get_tree().get_edited_scene_root()
	else:
		target_viewport = editor_viewport.get_parent()


func _gui_update_edge_info_panel():
	# Don't update if already visible
	if gui_edge_info_panel.visible:
		return
	var indicies: Array[int] = [-1, -1]
	var override: SS2D_Material_Edge_Metadata = null
	if on_edge:
		var t: Transform2D = get_et() * shape.get_global_transform()
		var offset: float = shape.get_closest_offset_straight_edge(t.affine_inverse() * edge_point)
		var keys: Array[int] = _get_edge_point_keys_from_offset(offset, true)
		indicies = [shape.get_point_index(keys[0]), shape.get_point_index(keys[1])]
		if shape.get_point_array().has_material_override(keys):
			override = shape.get_point_array().get_material_override(keys)
	gui_edge_info_panel.set_indicies(indicies)
	if override != null:
		gui_edge_info_panel.set_material_override(true)
		gui_edge_info_panel.load_values_from_meta_material(override)
	else:
		gui_edge_info_panel.set_material_override(false)

	# Shrink panel to minimum size
	gui_edge_info_panel.size = Vector2(1, 1)


func _gui_update_info_panels() -> void:
	if not is_2d_screen_active:
		_gui_hide_info_panels()
		return
	match current_mode:
		MODE.EDIT_VERT:
			_gui_update_vert_info_panel()
			gui_edge_info_panel.visible = false
		MODE.EDIT_EDGE:
			_gui_update_edge_info_panel()
			gui_point_info_panel.visible = false


func _gui_hide_info_panels() -> void:
	gui_edge_info_panel.visible = false
	gui_point_info_panel.visible = false

#########
# GODOT #
#########


# Called when saving
# https://docs.godotengine.org/en/3.2/classes/class_editorplugin.html?highlight=switch%20scene%20tab
func _apply_changes() -> void:
	gui_point_info_panel.visible = false
	gui_edge_info_panel.visible = false


func _init() -> void:
	pass


func _ready() -> void:
	# Support the undo-redo actions
	_gui_build_toolbar()
	add_child(gui_point_info_panel)
	gui_point_info_panel.visible = false
	add_child(gui_edge_info_panel)
	gui_edge_info_panel.visible = false
	gui_edge_info_panel.connect("material_override_toggled", self._on_edge_material_override_toggled)
	gui_edge_info_panel.connect("render_toggled", self._on_edge_material_override_render_toggled)
	gui_edge_info_panel.connect("weld_toggled", self._on_edge_material_override_weld_toggled)
	gui_edge_info_panel.connect("z_index_changed", self._on_edge_material_override_z_index_changed)
	gui_edge_info_panel.connect("edge_material_changed", self._on_edge_material_changed)
	add_child(gui_snap_settings)
	gui_snap_settings.hide()

	connect("main_screen_changed", self._on_main_screen_changed)


func _enter_tree() -> void:
	plugin = preload("res://addons/rmsmartshape/inpsector_plugin.gd").new()
	if plugin != null:
		add_inspector_plugin(plugin)

	pass


func _exit_tree() -> void:
	if (plugin != null):
		remove_inspector_plugin(plugin)

	gui_point_info_panel.visible = false
	gui_edge_info_panel.visible = false
	remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, tb_hb)
	tb_hb.queue_free()


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not is_shape_valid(shape):
		return false

	# Force update if global transforma has been changed
	if cached_shape_global_transform != shape.get_global_transform():
		shape.set_as_dirty()
		cached_shape_global_transform = shape.get_global_transform()

	var et: Transform2D = get_et()
	var grab_threshold: float = get_editor_interface().get_editor_settings().get(
		"editors/polygon_editor/point_grab_radius"
	)

	var key_return_value := false
	if event is InputEventKey:
		key_return_value = _input_handle_keyboard_event(event)

	var mb_return_value := false
	if event is InputEventMouseButton:
		mb_return_value = _input_handle_mouse_button_event(event, et, grab_threshold)

	var mm_return_value := false
	if event is InputEventMouseMotion:
		mb_return_value = _input_handle_mouse_motion_event(event, et, grab_threshold)

	var return_value := key_return_value == true or mb_return_value == true or mm_return_value == true
	_gui_update_info_panels()
	return return_value


func _handles(object: Object) -> bool:
	var hideToolbar: bool = true

	update_overlays()
	gui_point_info_panel.visible = false
	gui_edge_info_panel.visible = false

	var selection: EditorSelection = get_editor_interface().get_selection()
	if selection != null:
		if selection.get_selected_nodes().size() == 1:
			if selection.get_selected_nodes()[0] is SS2D_Shape_Base:
				hideToolbar = false

	if hideToolbar == true:
		tb_hb.hide()

	if object is Resource:
		return false

	return object is SS2D_Shape_Base


func _edit(object: Object) -> void:
	on_edge = false
	deselect_verts()
	if is_shape_valid(shape):
		disconnect_shape(shape)

	shape = null

	tb_hb.show()

	shape = object

	if not is_shape_valid(shape):
		gui_point_info_panel.visible = false
		gui_edge_info_panel.visible = false
		shape = null
	else:
		connect_shape(shape)

	update_overlays()


func _make_visible(_visible: bool) -> void:
	pass


func _on_main_screen_changed(screen_name: String) -> void:
	is_2d_screen_active = screen_name == "2D"
	if not is_2d_screen_active:
		_gui_hide_info_panels()


############
# SNAPPING #
############
func use_global_snap() -> bool:
	return ! tb_snap_popup.is_item_checked(1)


func use_snap() -> bool:
	return tb_snap_popup.is_item_checked(0)


func get_snap_offset() -> Vector2:
	return gui_snap_settings.get_snap_offset()


func get_snap_step() -> Vector2:
	return gui_snap_settings.get_snap_step()


func snap(v: Vector2, force: bool = false) -> Vector2:
	if not use_snap() and not force:
		return v
	var step: Vector2 = get_snap_step()
	var offset: Vector2 = get_snap_offset()
	var t := Transform2D.IDENTITY
	if use_global_snap():
		t = shape.get_global_transform()
	return snap_position(v, offset, step, t)


static func snap_position(
	pos_global: Vector2, snap_offset: Vector2, snap_step: Vector2, local_t: Transform2D
) -> Vector2:
	# Move global position to local position to snap in local space
	var pos_local: Vector2 = local_t * pos_global

	# Snap in local space
	var x: float = pos_local.x
	if snap_step.x != 0:
		var delta: float = fmod(pos_local.x, snap_step.x)
		# Round up
		if delta >= (snap_step.x / 2.0):
			x = pos_local.x + (snap_step.x - delta)
		# Round down
		else:
			x = pos_local.x - delta
	var y: float = pos_local.y
	if snap_step.y != 0:
		var delta: float = fmod(pos_local.y, snap_step.y)
		# Round up
		if delta >= (snap_step.y / 2.0):
			y = pos_local.y + (snap_step.y - delta)
		# Round down
		else:
			y = pos_local.y - delta

	# Transform3D local position to global position
	var pos_global_snapped := (local_t.affine_inverse() * Vector2(x, y)) + snap_offset
	#print ("%s | %s | %s | %s" % [pos_global, pos_local, Vector2(x,y), pos_global_snapped])
	return pos_global_snapped


##########
# PLUGIN #
##########

func disconnect_shape(s) -> void:
	if s.is_connected("points_modified", self._on_shape_point_modified):
		s.disconnect("points_modified", self._on_shape_point_modified)


func connect_shape(s) -> void:
	if not s.is_connected("points_modified", self._on_shape_point_modified):
		s.connect("points_modified", self._on_shape_point_modified)


static func get_material_override_from_indicies(
	s: SS2D_Shape_Base, indicies: Array
) -> SS2D_Material_Edge_Metadata:
	var keys: Array[int] = []
	for i in indicies:
		keys.push_back(s.get_point_key_at_index(i))
	if not s.get_point_array().has_material_override(keys):
		return null
	return s.get_point_array().get_material_override(keys)


func _on_edge_material_override_render_toggled(enabled: bool) -> void:
	var override := get_material_override_from_indicies(shape, gui_edge_info_panel.indicies)
	if override != null:
		override.render = enabled


func _on_edge_material_override_weld_toggled(enabled: bool) -> void:
	var override := get_material_override_from_indicies(shape, gui_edge_info_panel.indicies)
	if override != null:
		override.weld = enabled


func _on_edge_material_override_z_index_changed(z: int) -> void:
	var override := get_material_override_from_indicies(shape, gui_edge_info_panel.indicies)
	if override != null:
		override.z_index = z


func _on_edge_material_changed(m: SS2D_Material_Edge) -> void:
	var override := get_material_override_from_indicies(shape, gui_edge_info_panel.indicies)
	if override != null:
		override.edge_material = m


func _on_edge_material_override_toggled(enabled: bool) -> void:
	var indicies: Array[int] = gui_edge_info_panel.indicies
	if indicies.has(-1) or indicies.size() != 2:
		return
	var keys: Array[int] = []
	for i in indicies:
		keys.push_back(shape.get_point_key_at_index(i))

	# Get the relevant Override data if any exists
	var override = null
	if shape.get_point_array().has_material_override(keys):
		override = shape.get_point_array().get_material_override(keys)

	if enabled:
		if override == null:
			override = SS2D_Material_Edge_Metadata.new()
			override.edge_material = null
			shape.get_point_array().set_material_override(keys, override)

		# Load override data into the info panel
		gui_edge_info_panel.load_values_from_meta_material(override)
	else:
		if override != null:
			shape.get_point_array().remove_material_override(keys)


static func is_shape_valid(s) -> bool:
	if s == null:
		return false
	if not is_instance_valid(s):
		return false
	if not s.is_inside_tree():
		return false
	return true


func _on_shape_point_modified() -> void:
	FUNC.action_invert_orientation(self, "update_overlays", get_undo_redo(), shape)


func get_et() -> Transform2D:
	return get_editor_interface().get_edited_scene_root().get_viewport().global_canvas_transform


static func is_key_valid(s: SS2D_Shape_Base, key: int) -> bool:
	if not is_shape_valid(s):
		return false
	return s.has_point(key)


func _enter_mode(mode: int) -> void:
	if current_mode == mode:
		return
	for tb in [tb_vert_edit, tb_edge_edit, tb_pivot, tb_vert_create, tb_freehand]:
		tb.button_pressed = false

	previous_mode = current_mode
	current_mode = mode
	match mode:
		MODE.CREATE_VERT:
			tb_vert_create.button_pressed = true
		MODE.EDIT_VERT:
			tb_vert_edit.button_pressed = true
		MODE.EDIT_EDGE:
			tb_edge_edit.button_pressed = true
		MODE.SET_PIVOT:
			tb_pivot.button_pressed = true
		MODE.FREEHAND:
			tb_freehand.button_pressed = true
		_:
			tb_vert_edit.button_pressed = true
	update_overlays()


func _set_pivot(point: Vector2) -> void:
	var np: Vector2 = point
	var ct: Transform2D = shape.get_global_transform()
	ct.origin = np

	shape.disable_constraints()
	for i in shape.get_point_count():
		var key: int = shape.get_point_key_at_index(i)
		var pt: Vector2 = shape.get_global_transform() * shape.get_point_position(key)
		shape.set_point_position(key, ct.affine_inverse() * pt)
	shape.enable_constraints()

	shape.position = shape.get_parent().get_global_transform().affine_inverse() * np
	_enter_mode(current_mode)
	update_overlays()


func _add_collision() -> void:
	call_deferred("_add_deferred_collision")


func _add_deferred_collision() -> void:
	if not shape.get_parent() is StaticBody2D:
		var static_body: StaticBody2D = StaticBody2D.new()
		static_body.position = shape.position
		shape.position = Vector2.ZERO

		shape.get_parent().add_child(static_body)
		static_body.owner = get_editor_interface().get_edited_scene_root()

		shape.get_parent().remove_child(shape)
		static_body.add_child(shape)
		shape.owner = get_editor_interface().get_edited_scene_root()

		var poly: CollisionPolygon2D = CollisionPolygon2D.new()
		static_body.add_child(poly)
		poly.owner = get_editor_interface().get_edited_scene_root()
		# TODO: Make this a option at some point
		poly.modulate.a = 0.3
		poly.visible = false
		shape.collision_polygon_node_path = shape.get_path_to(poly)
		shape.set_as_dirty()


#############
# RENDERING #
#############
func _forward_canvas_draw_over_viewport(overlay: Control):
	# Something might force a draw which we had no control over,
	# in this case do some updating to be sure
	if not is_shape_valid(shape) or not is_inside_tree():
		return

	match current_mode:
		MODE.CREATE_VERT:
			draw_mode_edit_vert(overlay)
			if Input.is_key_pressed(KEY_ALT) and Input.is_key_pressed(KEY_SHIFT):
				draw_new_shape_preview(overlay)
			elif Input.is_key_pressed(KEY_ALT):
				draw_new_point_close_preview(overlay)
			else:
				draw_new_point_preview(overlay)
		MODE.EDIT_VERT:
			draw_mode_edit_vert(overlay)
			if Input.is_key_pressed(KEY_ALT):
				if Input.is_key_pressed(KEY_SHIFT):
					draw_new_shape_preview(overlay)
				elif not on_edge:
					draw_new_point_close_preview(overlay)
		MODE.EDIT_EDGE:
			draw_mode_edit_edge(overlay)
		MODE.FREEHAND:
			if not _mouse_lmb_pressed:
				draw_new_point_close_preview(overlay)
			draw_freehand_circle(overlay)
			draw_mode_edit_vert(overlay, false)


	shape.queue_redraw()


func draw_freehand_circle(overlay: Control) -> void:
	var mouse: Vector2 = overlay.get_local_mouse_position()
	var size: float = freehand_paint_size
	var color := Color.WHITE
	if Input.is_key_pressed(KEY_CTRL):
		color = Color.RED
		size = freehand_erase_size
	color.a = 0.5
	overlay.draw_arc(mouse, size * 2 * current_zoom_level, 0, TAU, 64, color, 1, true)
	color.a = 0.05
	overlay.draw_circle(mouse, size * 2 * current_zoom_level, color)


func draw_mode_edit_edge(overlay: Control) -> void:
	var t: Transform2D = get_et() * shape.get_global_transform()
	var verts: PackedVector2Array = shape.get_vertices()

	var color_highlight := Color(1.0, 0.75, 0.75, 1.0)
	var color_normal := Color(1.0, 0.25, 0.25, 0.8)

	draw_shape_outline(overlay, t, verts, color_normal, 3.0)
	draw_vert_handles(overlay, t, verts, false)

	if current_action.type == ACTION_VERT.MOVE_VERT:
		var edge_point_keys: Array[int] = current_action.keys
		var p1: Vector2 = shape.get_point_position(edge_point_keys[0])
		var p2: Vector2 = shape.get_point_position(edge_point_keys[1])
		overlay.draw_line(t * p1, t * p2, color_highlight, 5.0)
	elif on_edge:
		var offset: float = shape.get_closest_offset_straight_edge(t.affine_inverse() * edge_point)
		var edge_point_keys: Array[int] = _get_edge_point_keys_from_offset(offset, true)
		var p1: Vector2 = shape.get_point_position(edge_point_keys[0])
		var p2: Vector2 = shape.get_point_position(edge_point_keys[1])
		overlay.draw_line(t * p1, t * p2, color_highlight, 5.0)


func draw_mode_edit_vert(overlay: Control, show_vert_handles: bool = true) -> void:
	var t: Transform2D = get_et() * shape.get_global_transform()
	var verts: PackedVector2Array = shape.get_vertices()
	var points: PackedVector2Array = shape.get_tessellated_points()
	draw_shape_outline(overlay, t, points)
	if show_vert_handles:
		draw_vert_handles(overlay, t, verts, true)
	if on_edge:
		overlay.draw_texture(ICON_ADD_HANDLE, edge_point - ICON_ADD_HANDLE.get_size() * 0.5)

	# Draw Highlighted Handle
	if current_action.is_single_vert_selected():
		var tex: Texture2D = ICON_HANDLE_SELECTED
		overlay.draw_texture(
			tex, t * verts[current_action.current_point_index(shape)] - tex.get_size() * 0.5
		)


func draw_shape_outline(
	overlay: Control, t: Transform2D, points: PackedVector2Array, color = null, width = 2.0
) -> void:
	# Draw Outline
	var prev_pt: Vector2
	if color == null:
		color = shape.modulate
	for i in range(0, points.size(), 1):
		var pt: Vector2 = points[i]
		if i > 0:
			overlay.draw_line(prev_pt, t * pt, color, width)
		prev_pt = t * pt


func draw_vert_handles(
	overlay: Control, t: Transform2D, verts: PackedVector2Array, control_points: bool
) -> void:
	for i in range(0, verts.size(), 1):
		# Draw Vert handles
		var hp: Vector2 = t * verts[i]
		var icon: Texture2D = ICON_HANDLE_BEZIER if (Input.is_key_pressed(KEY_SHIFT) and not current_mode == MODE.FREEHAND) else ICON_HANDLE
		overlay.draw_texture(icon, hp - icon.get_size() * 0.5)

		# Draw Width handles
#		var normal = _get_vert_normal(t, verts, i)
#		var width_handle_icon = WIDTH_HANDLES[int((normal.angle() + PI / 8 + TAU) / PI * 4) % 4]
#		overlay.draw_texture(width_handle_icon, hp - width_handle_icon.get_size() * 0.5 + normal * WIDTH_HANDLE_OFFSET)

	# Draw Width handle
	var offset: float = WIDTH_HANDLE_OFFSET
	var width_handle_key: int = closest_key
	if (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		and current_action.type == ACTION_VERT.MOVE_WIDTH_HANDLE
	):
		offset *= width_scaling
		width_handle_key = current_action.keys[0]

	var point_index: int = shape.get_point_index(width_handle_key)
	if point_index == -1:
		return

	var width_handle_normal: Vector2 = _get_vert_normal(t, verts, point_index)
	var vertex_position: Vector2 = t * shape.get_point_position(width_handle_key)
	var icon_position: Vector2 = vertex_position + width_handle_normal * offset
	var size: Vector2 = Vector2.ONE * 10.0
	var width_handle_color := Color("f53351")
	overlay.draw_line(vertex_position, icon_position, width_handle_color, 1.0)
	overlay.draw_set_transform(icon_position, width_handle_normal.angle(), Vector2.ONE)
	overlay.draw_rect(Rect2(-size / 2.0, size), width_handle_color, true)
	overlay.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Draw Control point handles
	if control_points:
		for i in range(0, verts.size(), 1):
			var key: int = shape.get_point_key_at_index(i)
			var hp: Vector2 = t * verts[i]

			# Drawing the point-out for the last point makes no sense, as there's no point ahead of it
			if i < verts.size() - 1:
				var pointout: Vector2 = t * (verts[i] + shape.get_point_out(key))
				if hp != pointout:
					_draw_control_point_line(overlay, hp, pointout, ICON_HANDLE_CONTROL)
			# Drawing the point-in for point 0 makes no sense, as there's no point behind it
			if i > 0:
				var pointin: Vector2 = t * (verts[i] + shape.get_point_in(key))
				if hp != pointin:
					_draw_control_point_line(overlay, hp, pointin, ICON_HANDLE_CONTROL)


func _draw_control_point_line(c: Control, vert: Vector2, cp: Vector2, tex: Texture2D) -> void:
	# Draw the line with a dark and light color to be visible on all backgrounds
	var color_dark := Color(0, 0, 0, 0.3)
	var color_light := Color(1, 1, 1, .5)
	var width := 2.0
	var normal := (cp - vert).normalized()
	c.draw_line(vert + normal * 4 + Vector2.DOWN, cp + Vector2.DOWN, color_dark, width)
	c.draw_line(vert + normal * 4, cp, color_light, width)
	c.draw_texture(tex, cp - tex.get_size() * 0.5)


func draw_new_point_preview(overlay: Control) -> void:
	# Draw lines to where a new point will be added
	var verts: PackedVector2Array = shape.get_vertices()
	var t: Transform2D = get_et() * shape.get_global_transform()
	var color := Color(1, 1, 1, .5)
	var width := 2.0
	var mouse: Vector2 = overlay.get_local_mouse_position()

	if verts.size() > 0:
		var a: Vector2
		if is_shape_closed(shape) and verts.size() > 1:
			a = t * verts[verts.size() - 2]
			overlay.draw_line(mouse, t * verts[0], color,width * .5)
		else:
			a = t * verts[verts.size() - 1]
		overlay.draw_line(mouse, a, color, width)

	overlay.draw_texture(ICON_ADD_HANDLE, mouse - ICON_ADD_HANDLE.get_size() * 0.5)


func draw_new_point_close_preview(overlay: Control) -> void:
	# Draw lines to where a new point will be added
	var t: Transform2D = get_et() * shape.get_global_transform()
	var color := Color(1, 1, 1, .5)
	var width := 2.0

	var mouse: Vector2 = overlay.get_local_mouse_position()
	var a: Vector2 = t * shape.get_point_position(closest_edge_keys[0])
	var b: Vector2 = t * shape.get_point_position(closest_edge_keys[1])
	overlay.draw_line(mouse, a, color, width)
	color.a = 0.1
	overlay.draw_line(mouse, b, color, width)
	overlay.draw_texture(ICON_ADD_HANDLE, mouse - ICON_ADD_HANDLE.get_size() * 0.5)


func draw_new_shape_preview(overlay: Control) -> void:
	# Draw a plus where a new shape will be added
	var mouse: Vector2 = overlay.get_local_mouse_position()
	overlay.draw_texture(ICON_ADD_HANDLE, mouse - ICON_ADD_HANDLE.get_size() * 0.5)


##########
# PLUGIN #
##########
func deselect_verts() -> void:
	current_action = ActionDataVert.new([], [], [], [], [], ACTION_VERT.NONE)


func select_verticies(keys: Array[int], action: ACTION_VERT) -> ActionDataVert:
	var from_positions := PackedVector2Array()
	var from_positions_c_in := PackedVector2Array()
	var from_positions_c_out := PackedVector2Array()
	var from_widths: Array[float] = []
	for key in keys:
		from_positions.push_back(shape.get_point_position(key))
		from_positions_c_in.push_back(shape.get_point_in(key))
		from_positions_c_out.push_back(shape.get_point_out(key))
		from_widths.push_back(shape.get_point_width(key))
	return ActionDataVert.new(
		keys, from_positions, from_positions_c_in, from_positions_c_out, from_widths, action
	)


func select_vertices_to_move(keys: Array[int], _mouse_starting_pos_viewport: Vector2) -> void:
	_mouse_motion_delta_starting_pos = _mouse_starting_pos_viewport
	current_action = select_verticies(keys, ACTION_VERT.MOVE_VERT)


func select_control_points_to_move(
	keys: Array[int], _mouse_starting_pos_viewport: Vector2, action = ACTION_VERT.MOVE_CONTROL
) -> void:
	current_action = select_verticies(keys, action)
	_mouse_motion_delta_starting_pos = _mouse_starting_pos_viewport


func select_width_handle_to_move(keys: Array[int], _mouse_starting_pos_viewport: Vector2) -> void:
	_mouse_motion_delta_starting_pos = _mouse_starting_pos_viewport
	current_action = select_verticies(keys, ACTION_VERT.MOVE_WIDTH_HANDLE)


#########
# INPUT #
#########
func _input_handle_right_click_press(mb_position: Vector2, grab_threshold: float) -> bool:
	if not shape.can_edit:
		return false
	if current_mode == MODE.EDIT_VERT or current_mode == MODE.CREATE_VERT:
		# Mouse over a single vertex?
		if current_action.is_single_vert_selected():
			FUNC.action_delete_point(self, "update_overlays", get_undo_redo(), shape, current_action.keys[0])
			deselect_verts()
			return true
		else:
			# Mouse over a control point?
			var et: Transform2D = get_et()
			var points_in: Array = FUNC.get_intersecting_control_point_in(
				shape, et, mb_position, grab_threshold
			)
			var points_out: Array = FUNC.get_intersecting_control_point_out(
				shape, et, mb_position, grab_threshold
			)
			if not points_in.is_empty():
				FUNC.action_delete_point_in(self, "update_overlays", get_undo_redo(), shape, points_in[0])
				return true
			elif not points_out.is_empty():
				FUNC.action_delete_point_out(self, "update_overlays", get_undo_redo(), shape, points_out[0])
				return true
	elif current_mode == MODE.EDIT_EDGE:
		if on_edge:
			gui_edge_info_panel.visible = not gui_edge_info_panel.visible
			gui_edge_info_panel.position = get_window().get_mouse_position()
			return true
	return false


func _input_handle_left_click(
	mb: InputEventMouseButton,
	vp_m_pos: Vector2,
	t: Transform2D,
	et: Transform2D,
	grab_threshold: float
) -> bool:
	# Set Pivot?
	if current_mode == MODE.SET_PIVOT:
		var local_position: Vector2 = et.affine_inverse() * mb.position
		if use_snap():
			local_position = snap(local_position)
		FUNC.action_set_pivot(self, "_set_pivot", get_undo_redo(), shape, et, local_position)
		return true
	if current_mode == MODE.EDIT_VERT or current_mode == MODE.CREATE_VERT:
		gui_edge_info_panel.visible = false

		# Any nearby control points to move?
		if not Input.is_key_pressed(KEY_ALT):
			if _input_move_control_points(mb, vp_m_pos, grab_threshold):
				return true

			# Highlighting a vert to move or add control points to
			if current_action.is_single_vert_selected():
				if on_width_handle:
					select_width_handle_to_move([current_action.current_point_key()], vp_m_pos)
				elif Input.is_key_pressed(KEY_SHIFT):
					select_control_points_to_move([current_action.current_point_key()], vp_m_pos)
					return true
				else:
					select_vertices_to_move([current_action.current_point_key()], vp_m_pos)
					return true

		# Split the Edge?
		if _input_split_edge(mb, vp_m_pos, t):
			return true

		if not on_edge:
			# Create new point
			if Input.is_key_pressed(KEY_ALT) or current_mode == MODE.CREATE_VERT:
				var local_position: Vector2 = t.affine_inverse() * mb.position
				if use_snap():
					local_position = snap(local_position)
				if Input.is_key_pressed(KEY_SHIFT) and Input.is_key_pressed(KEY_ALT):
					# Copy shape with a new single point
					var copy: SS2D_Shape_Base = copy_shape(shape)

					copy.set_point_array(SS2D_Point_Array.new())
					var new_key: int = FUNC.action_add_point(
						self, "update_overlays", get_undo_redo(), copy, local_position
					)
					select_vertices_to_move([new_key], vp_m_pos)

					_enter_mode(MODE.CREATE_VERT)

					var selection := get_editor_interface().get_selection()
					selection.clear()
					selection.add_node(copy)
				elif Input.is_key_pressed(KEY_ALT):
					FUNC.action_add_point(
						self,
						"update_overlays",
						get_undo_redo(),
						shape,
						local_position,
						shape.get_point_index(closest_edge_keys[1])
					)
				else:
					var new_key: int = FUNC.action_add_point(
						self, "update_overlays", get_undo_redo(), shape, local_position
					)
					select_vertices_to_move([new_key], vp_m_pos)
				return true
	elif current_mode == MODE.EDIT_EDGE:
		if gui_edge_info_panel.visible:
			gui_edge_info_panel.visible = false
			return true
		if on_edge:
			# Grab Edge (2 points)
			var offset: float = shape.get_closest_offset_straight_edge(
				t.affine_inverse() * edge_point
			)
			var edge_point_keys: Array[int] = _get_edge_point_keys_from_offset(offset, true)
			select_vertices_to_move([edge_point_keys[0], edge_point_keys[1]], vp_m_pos)
		return true
	elif current_mode == MODE.FREEHAND:
		return true
	return false


func _input_handle_mouse_wheel(btn: int) -> bool:
	if current_mode == MODE.FREEHAND:
		if Input.is_key_pressed(KEY_CTRL) and Input.is_key_pressed(KEY_SHIFT):
			var step_multiplier := 1.2 if btn == MOUSE_BUTTON_WHEEL_UP else 0.8
			freehand_erase_size = roundf(clampf(freehand_erase_size * step_multiplier, 5, 400))
			update_overlays()
			return true
		elif Input.is_key_pressed(KEY_SHIFT):
			var step_multiplier := 1.2 if btn == MOUSE_BUTTON_WHEEL_UP else 0.8
			freehand_paint_size = roundf(clampf(freehand_paint_size * step_multiplier, 5, 400))
			update_overlays()
			return true
	elif current_action.is_single_vert_selected():
		if not shape.can_edit:
			return false
		var key: int = current_action.current_point_key()
		if Input.is_key_pressed(KEY_SHIFT):
			var width: float = shape.get_point_width(key)
			var width_step := 0.1
			if btn == MOUSE_BUTTON_WHEEL_DOWN:
				width_step *= -1
			var new_width: float = width + width_step
			shape.set_point_width(key, new_width)

		else:
			var texture_idx_step := 1
			if btn == MOUSE_BUTTON_WHEEL_DOWN:
				texture_idx_step *= -1

			var tex_idx: int = shape.get_point_texture_index(key) + texture_idx_step
			shape.set_point_texture_index(key, tex_idx)

		shape.set_as_dirty()
		update_overlays()
		_gui_update_info_panels()
		return true

	return false


func _input_handle_keyboard_event(event: InputEventKey) -> bool:
	if not shape.can_edit:
		return false
	var kb: InputEventKey = event
	if _is_valid_keyboard_scancode(kb):
		if current_action.is_single_vert_selected():
			if kb.pressed and kb.keycode == KEY_SPACE:
				var key: int = current_action.current_point_key()
				shape.set_point_texture_flip(key, not shape.get_point_texture_flip(key))
				shape.set_as_dirty()
				shape.queue_redraw()
				_gui_update_info_panels()

		if kb.pressed and kb.keycode == KEY_ESCAPE:
			# Hide edge_info_panel
			if gui_edge_info_panel.visible:
				gui_edge_info_panel.visible = false

			if current_mode == MODE.CREATE_VERT:
				_enter_mode(MODE.EDIT_VERT)

		if kb.keycode == KEY_CTRL:
			if kb.pressed and not kb.echo:
				on_edge = false
				current_action = select_verticies([closest_key], ACTION_VERT.NONE)
			else:
				deselect_verts()
			update_overlays()

		if kb.keycode == KEY_ALT:
			update_overlays()

		return true
	return false


func _is_valid_keyboard_scancode(kb: InputEventKey) -> bool:
	match kb.keycode:
		KEY_ESCAPE:
			return true
		KEY_ENTER:
			return true
		KEY_SPACE:
			return true
		KEY_SHIFT:
			return true
		KEY_ALT:
			return true
		KEY_CTRL:
			return true
	return false


func _input_handle_mouse_button_event(
	event: InputEventMouseButton, et: Transform2D, grab_threshold: float
) -> bool:
	if not shape.can_edit:
		return false
	var t: Transform2D = et * shape.get_global_transform()
	var mb: InputEventMouseButton = event
	var viewport_mouse_position: Vector2 = et.affine_inverse() * mb.position
	var mouse_wheel_spun: bool = (
		mb.pressed
		and (mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_UP)
	)

	#######################################
	# Left Mouse Button released
	if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_mouse_lmb_pressed = false
		var rslt: bool = false
		var type: ACTION_VERT = current_action.type
		var _in := type == ACTION_VERT.MOVE_CONTROL or type == ACTION_VERT.MOVE_CONTROL_IN
		var _out := type == ACTION_VERT.MOVE_CONTROL or type == ACTION_VERT.MOVE_CONTROL_OUT
		if type == ACTION_VERT.MOVE_VERT:
			FUNC.action_move_verticies(self, "update_overlays", get_undo_redo(), shape, current_action)
			rslt = true
		elif _in or _out:
			FUNC.action_move_control_points(
				self, "update_overlays", get_undo_redo(), shape, current_action, _in, _out
			)
			rslt = true
		deselect_verts()
		return rslt

	#######################################
	# Right Mouse Button released
	if not mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_mouse_rmb_pressed = false

	#########################################
	# Mouse Wheel on valid point
	elif mouse_wheel_spun:
		return _input_handle_mouse_wheel(mb.button_index)

	#########################################
	# Mouse left click
	elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_mouse_lmb_pressed = true
		return _input_handle_left_click(mb, viewport_mouse_position, t, et, grab_threshold)

	#########################################
	# Mouse right click
	elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_mouse_rmb_pressed = true
		return _input_handle_right_click_press(mb.position, grab_threshold)

	return false


func _input_split_edge(mb: InputEventMouseButton, vp_m_pos: Vector2, t: Transform2D) -> bool:
	if not on_edge:
		return false
	var gpoint: Vector2 = mb.position
	var insertion_point: int = -1
	var mb_offset: float = shape.get_closest_offset(t.affine_inverse() * gpoint)

	insertion_point = shape.get_point_index(_get_edge_point_keys_from_offset(mb_offset)[1])

	if insertion_point == -1:
		insertion_point = shape.get_point_count() - 1

	var key: int = FUNC.action_split_curve(
		self, "update_overlays", get_undo_redo(), shape, insertion_point, gpoint, t
	)
	select_vertices_to_move([key], vp_m_pos)
	on_edge = false

	return true


func _input_move_control_points(mb: InputEventMouseButton, vp_m_pos: Vector2, grab_threshold: float) -> bool:
	var points_in: Array[int] = FUNC.get_intersecting_control_point_in(
		shape, get_et(), mb.position, grab_threshold
	)
	var points_out: Array[int] = FUNC.get_intersecting_control_point_out(
		shape, get_et(), mb.position, grab_threshold
	)
	if not points_in.is_empty():
		select_control_points_to_move([points_in[0]], vp_m_pos, ACTION_VERT.MOVE_CONTROL_IN)
		return true
	elif not points_out.is_empty():
		select_control_points_to_move([points_out[0]], vp_m_pos, ACTION_VERT.MOVE_CONTROL_OUT)
		return true
	return false


func _get_edge_point_keys_from_offset(
	offset: float, straight: bool = false, _position := Vector2(0, 0)
) -> Array[int]:
	for i in range(0, shape.get_point_count() - 1, 1):
		var key: int = shape.get_point_key_at_index(i)
		var key_next: int = shape.get_point_key_at_index(i + 1)
		var this_offset := 0.0
		var next_offset := 0.0
		if straight:
			this_offset = shape.get_closest_offset_straight_edge(shape.get_point_position(key))
			next_offset = shape.get_closest_offset_straight_edge(shape.get_point_position(key_next))
		else:
			this_offset = shape.get_closest_offset(shape.get_point_position(key))
			next_offset = shape.get_closest_offset(shape.get_point_position(key_next))

		if offset >= this_offset and offset <= next_offset:
			return [key, key_next]
		# for when the shape is closed and the final point has an offset of 0
		if next_offset == 0 and offset >= this_offset:
			return [key, key_next]
	return [-1, -1]


func _input_motion_is_on_edge(mm: InputEventMouseMotion, grab_threshold: float) -> bool:
	var xform: Transform2D = get_et() * shape.get_global_transform()
	if shape.get_point_count() < 2:
		return false

	# Find edge
	var closest_point: Vector2
	if current_mode == MODE.EDIT_EDGE:
		closest_point = shape.get_closest_point_straight_edge(
			xform.affine_inverse() * mm.position
		)
	else:
		closest_point = shape.get_closest_point(xform.affine_inverse() * mm.position)
	edge_point = xform * closest_point
	if edge_point.distance_to(mm.position) <= grab_threshold:
		return true
	return false


func _input_find_closest_edge_keys(mm: InputEventMouseMotion) -> void:
	if shape.get_point_count() < 2:
		return

	# Find edge
	var xform: Transform2D = get_et() * shape.get_global_transform()
	var closest_point: Vector2 = shape.get_closest_point_straight_edge(xform.affine_inverse() * mm.position)
	var edge_p: Vector2 = xform * closest_point
	var offset: float = shape.get_closest_offset_straight_edge(xform.affine_inverse() * edge_p)
	closest_edge_keys = _get_edge_point_keys_from_offset(offset, true, xform.affine_inverse() * mm.position)


func get_mouse_over_vert_key(mm: InputEventMouseMotion, grab_threshold: float) -> int:
	var xform: Transform2D = get_et() * shape.get_global_transform()
	# However, if near a control point or one of its handles then we are not on the edge
	for k in shape.get_all_point_keys():
		var pp: Vector2 = shape.get_point_position(k)
		var p: Vector2 = xform * pp
		if p.distance_to(mm.position) <= grab_threshold:
			return k
	return -1


func get_mouse_over_width_handle(mm: InputEventMouseMotion, grab_threshold: float) -> int:
	var xform: Transform2D = get_et() * shape.get_global_transform()
	for k in shape.get_all_point_keys():
		var pp: Vector2 = shape.get_point_position(k)
		var normal: Vector2 = _get_vert_normal(
			xform, shape.get_vertices(), shape.get_point_index(k)
		)
		var p: Vector2 = xform * pp + normal * WIDTH_HANDLE_OFFSET
		if p.distance_to(mm.position) <= grab_threshold:
			return k
	return -1


func _input_motion_move_control_points(delta: Vector2, _in: bool, _out: bool) -> bool:
	var rslt := false
	for i in range(0, current_action.keys.size(), 1):
		var key: int = current_action.keys[i]
		var out_multiplier := 1
		# Invert the delta for position_out if moving both at once
		if _out and _in:
			out_multiplier = -1
		var new_position_in: Vector2 = delta + current_action.starting_positions_control_in[i]
		var new_position_out: Vector2 = (
			(delta * out_multiplier)
			+ current_action.starting_positions_control_out[i]
		)
		if use_snap():
			new_position_in = snap(new_position_in)
			new_position_out = snap(new_position_out)
		if _in:
			shape.set_point_in(key, new_position_in)
			rslt = true
		if _out:
			shape.set_point_out(key, new_position_out)
			rslt = true
		shape.set_as_dirty()
		update_overlays()

	# TODO: should this always be false? rslt is set but unused
	return false


func _input_motion_move_verts(delta: Vector2) -> bool:
	for i in range(0, current_action.keys.size(), 1):
		var key: int = current_action.keys[i]
		var from: Vector2 = current_action.starting_positions[i]
		var new_position: Vector2 = from + delta
		if use_snap():
			new_position = snap(new_position)
		shape.set_point_position(key, new_position)
		update_overlays()
	return true


func _input_motion_move_width_handle(mouse_position: Vector2, scale: Vector2) -> bool:
	for i in range(0, current_action.keys.size(), 1):
		var key: int = current_action.keys[i]
		var from_width: float = current_action.starting_width[i]
		var from_position: Vector2 = current_action.starting_positions[i]
		width_scaling = from_position.distance_to(mouse_position) / WIDTH_HANDLE_OFFSET * scale.x
		shape.set_point_width(key, roundf(from_width * width_scaling * 10.0) / 10.0)
		update_overlays()
	return true


## Will return index of closest vert to point.
func get_closest_vert_to_point(s: SS2D_Shape_Base, p: Vector2) -> int:
	var gt: Transform2D = shape.get_global_transform()
	var verts: PackedVector2Array = s.get_vertices()
	var transformed_point: Vector2 = gt.affine_inverse() * p
	var idx: int = -1
	var closest_distance: float = -1.0
	for i in verts.size():
		var distance: float = verts[i].distance_to(transformed_point)
		if distance < closest_distance or closest_distance == -1.0:
			idx = s.get_point_key_at_index(i)
			closest_distance = distance
	return idx


func _input_handle_mouse_motion_event(
	event: InputEventMouseMotion, et: Transform2D, grab_threshold: float
) -> bool:
	var t: Transform2D = et * shape.get_global_transform()
	var mm: InputEventMouseMotion = event
	var delta_current_pos: Vector2 = et.affine_inverse() * mm.position
	gui_point_info_panel.position = mm.position + GUI_POINT_INFO_PANEL_OFFSET
	var delta: Vector2 = delta_current_pos - _mouse_motion_delta_starting_pos

	closest_key = get_closest_vert_to_point(shape, delta_current_pos)

	if current_mode == MODE.EDIT_VERT or current_mode == MODE.CREATE_VERT:
		var type: ACTION_VERT = current_action.type
		var _in := type == ACTION_VERT.MOVE_CONTROL or type == ACTION_VERT.MOVE_CONTROL_IN
		var _out := type == ACTION_VERT.MOVE_CONTROL or type == ACTION_VERT.MOVE_CONTROL_OUT

		if type == ACTION_VERT.MOVE_VERT:
			return _input_motion_move_verts(delta)
		elif _in or _out:
			return _input_motion_move_control_points(delta, _in, _out)
		elif type == ACTION_VERT.MOVE_WIDTH_HANDLE:
			return _input_motion_move_width_handle(
				et.affine_inverse() * mm.position, et.get_scale()
			)
		var mouse_over_key: int = get_mouse_over_vert_key(event, grab_threshold)
		var mouse_over_width_handle: int = get_mouse_over_width_handle(event, grab_threshold)

		# Make the closest key grabable while holding down Control
		if (
			Input.is_key_pressed(KEY_CTRL)
			and not Input.is_key_pressed(KEY_ALT)
			and mouse_over_width_handle == -1
			and mouse_over_key == -1
		):
			mouse_over_key = closest_key

		on_width_handle = false
		if mouse_over_key != -1:
			on_edge = false
			current_action = select_verticies([mouse_over_key], ACTION_VERT.NONE)
		elif mouse_over_width_handle != -1:
			on_edge = false
			on_width_handle = true
			current_action = select_verticies([mouse_over_width_handle], ACTION_VERT.NONE)
		elif Input.is_key_pressed(KEY_ALT):
			_input_find_closest_edge_keys(mm)
		else:
			deselect_verts()
			on_edge = _input_motion_is_on_edge(mm, grab_threshold)

	elif current_mode == MODE.EDIT_EDGE:
		# Don't update if edge panel is visible
		if gui_edge_info_panel.visible:
			return false
		var type: ACTION_VERT = current_action.type
		if type == ACTION_VERT.MOVE_VERT:
			return _input_motion_move_verts(delta)
		else:
			deselect_verts()
		on_edge = _input_motion_is_on_edge(mm, grab_threshold)

	elif current_mode == MODE.FREEHAND:
		if _mouse_lmb_pressed:
			if not Input.is_key_pressed(KEY_CTRL):
				var local_position: Vector2 = t.affine_inverse() * mm.position
				if last_point_position.distance_to(local_position) >= freehand_paint_size * 2:
					last_point_position = local_position
					if use_snap():
						local_position = snap(local_position)
					FUNC.action_add_point(
						self,
						"update_overlays",
						get_undo_redo(),
						shape,
						local_position,
						shape.get_point_index(closest_edge_keys[1])
					)
				update_overlays()
				return true
			else:
				var xform: Transform2D = get_et() * shape.get_global_transform()
				var closest_ss2d_point: SS2D_Point = (shape as SS2D_Shape_Base).get_point(closest_key)
				if closest_ss2d_point != null:
					var closest_point: Vector2 = closest_ss2d_point.position
					closest_point = xform * closest_point
					if closest_point.distance_to(mm.position) / current_zoom_level <= freehand_erase_size * 2:
						var delete_point: int = get_mouse_over_vert_key(event, grab_threshold)
						delete_point = closest_key
						on_width_handle = false
						if delete_point != -1:
							FUNC.action_delete_point(self, "update_overlays", get_undo_redo(), shape, delete_point)
							last_point_position = Vector2.ZERO
							update_overlays()
							return true
		else:
			_input_find_closest_edge_keys(mm)

	update_overlays()
	return false


func _get_vert_normal(t: Transform2D, verts, i: int) -> Vector2:
	var point: Vector2 = t * verts[i]
	var prev_point: Vector2 = t * (verts[(i - 1) % verts.size()])
	var next_point: Vector2 = t * (verts[(i + 1) % verts.size()])
	return ((prev_point - point).normalized().rotated(PI / 2) + (point - next_point).normalized().rotated(PI / 2)).normalized()


func copy_shape(s: SS2D_Shape_Base) -> SS2D_Shape_Base:
	var copy: SS2D_Shape_Base
	if s is SS2D_Shape_Closed:
		copy = SS2D_Shape_Closed.new()
	if s is SS2D_Shape_Open:
		copy = SS2D_Shape_Open.new()
	if s is SS2D_Shape_Meta:
		copy = SS2D_Shape_Meta.new()
	copy.position = s.position
	copy.scale = s.scale
	copy.modulate = s.modulate
	copy.shape_material = s.shape_material
	copy.editor_debug = s.editor_debug
	copy.flip_edges = s.flip_edges
	copy.editor_debug = s.editor_debug
	copy.collision_size = s.collision_size
	copy.collision_offset = s.collision_offset
	copy.tessellation_stages = s.tessellation_stages
	copy.tessellation_tolerence = s.tessellation_tolerence
	copy.curve_bake_interval = s.curve_bake_interval
	#copy.material_overrides = s.material_overrides

	s.get_parent().add_child(copy)
	copy.set_owner(get_tree().get_edited_scene_root())

	if (
		not s.collision_polygon_node_path.is_empty()
		and s.has_node(s.collision_polygon_node_path)
	):
		var collision_polygon_original: Node = s.get_node(s.collision_polygon_node_path)
		var collision_polygon_new := CollisionPolygon2D.new()
		collision_polygon_new.visible = collision_polygon_original.visible

		collision_polygon_original.get_parent().add_child(collision_polygon_new)
		collision_polygon_new.set_owner(get_tree().get_edited_scene_root())

		copy.collision_polygon_node_path = copy.get_path_to(collision_polygon_new)

	return copy


func is_shape_closed(s: SS2D_Shape_Base) -> bool:
	if s is SS2D_Shape_Open:
		return false
	if s is SS2D_Shape_Meta:
		return shape.treat_as_closed()
	return true


#########
# DEBUG #
#########
func _debug_mouse_positions(mm, t):
	print("========================================")
	print("MouseDelta:%s" % str(_mouse_motion_delta_starting_pos))
	print("= MousePositions =")
	print("Position:  %s" % str(mm.position))
	print("Relative:  %s" % str(mm.relative))
	print("= Transforms =")
	print("Transform3D: %s" % str(t))
	print("Inverse:   %s" % str(t.affine_inverse()))
	print("= Transformed Mouse positions =")
	print("Position:  %s" % str(t.affine_inverse() * mm.position))
	print("Relative:  %s" % str(t.affine_inverse() * mm.relative))
	print("MouseDelta:%s" % str(t.affine_inverse() * _mouse_motion_delta_starting_pos))
