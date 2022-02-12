@tool
extends Resource
class_name SS2D_VertexProperties

@export var texture_idx : int: set = set_texture_idx
@export var flip: bool : set = set_flip
@export var width: float : set = set_width


func set_texture_idx(i: int):
    texture_idx = i
    emit_signal("changed")
    notify_property_list_changed()


func set_flip(b: bool):
    flip = b
    emit_signal("changed")
    notify_property_list_changed()


func set_width(w: float):
    width = w
    emit_signal("changed")
    notify_property_list_changed()


func _init():
    texture_idx = 0
    flip = false
    width = 1.0


# FIXME: See https://github.com/godotengine/godot/issues/58031
func duplicate_fixed(_sub_resources: bool = false) -> SS2D_VertexProperties:
    var _new = SS2D_VertexProperties.new()
    _new.texture_idx = texture_idx
    _new.flip = flip
    _new.width = width
    return _new


func equals(other: SS2D_VertexProperties) -> bool:
    if other.flip != flip:
        return false
    if other.texture_idx != texture_idx:
        return false
    if other.width != width:
        return false
    return true
