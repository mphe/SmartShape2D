@tool
extends Resource
class_name SS2D_Material_Shape

# This material represents the set of edge materials used for a RMSmartShape2D
# Each edge represents a set of textures used to render an edge

# List of materials this shape can use
# Should be SS2D_Material_Edge_Metadata
@export var _edge_meta_materials: Array[Resource] = [] : set = set_edge_meta_materials
@export var fill_textures: Array[Texture2D] = [] : set = set_fill_textures
@export var fill_texture_normals: Array[Texture2D] = [] : set = set_fill_texture_normals
@export var fill_texture_z_index: int = -10 : set = set_fill_texture_z_index
@export var fill_mesh_offset: float = 0.0 : set = set_fill_mesh_offset
@export var fill_mesh_material: Material = null : set = set_fill_mesh_material

# How much to offset all edges
# FIXME: Use @export_range(-1.5, 1.5, 0.1) when https://github.com/godotengine/godot/issues/41183 gets fixed
@export var render_offset: float = 0.0 : set = set_render_offset


func set_fill_mesh_material(m: Material):
    fill_mesh_material = m
    emit_signal("changed")


func set_fill_mesh_offset(f: float):
    fill_mesh_offset = f
    emit_signal("changed")


func set_render_offset(f: float):
    render_offset = f
    emit_signal("changed")


# Get all valid edge materials for this normal
func get_edge_meta_materials(normal: Vector2) -> Array:
    var materials = []
    for e in _edge_meta_materials:
        if e == null:
            continue
        if e.normal_range.is_in_range(normal):
            materials.push_back(e)
    return materials


func get_all_edge_meta_materials() -> Array:
    return _edge_meta_materials


func get_all_edge_materials() -> Array:
    var materials = []
    for meta in _edge_meta_materials:
        if meta.edge_material != null:
            materials.push_back(meta.edge_material)
    return materials


func add_edge_material(e: SS2D_Material_Edge_Metadata):
    var new_array = _edge_meta_materials.duplicate()
    new_array.push_back(e)
    set_edge_meta_materials(new_array)


func _on_edge_material_changed():
    emit_signal("changed")


func set_fill_textures(a):
    fill_textures = a
    emit_signal("changed")


func set_fill_texture_normals(a):
    fill_texture_normals = a
    emit_signal("changed")


func set_fill_texture_z_index(i: int):
    fill_texture_z_index = i
    emit_signal("changed")


func set_edge_meta_materials(a):
    for e in _edge_meta_materials:
        if e == null:
            continue
        if not a.has(e):
            e.disconnect("changed", self._on_edge_material_changed)

    for e in a:
        if e == null:
            continue
        if not e.is_connected("changed", self._on_edge_material_changed):
            e.connect("changed", self._on_edge_material_changed)

    _edge_meta_materials = a
    emit_signal("changed")
