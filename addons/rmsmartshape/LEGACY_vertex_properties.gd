extends RefCounted
class_name RMS2D_VertexProperties

var texture_idx:int = 0
var flip:bool = false
var width:float = 1.0

# FIXME: See https://github.com/godotengine/godot/issues/58031
func duplicate_fixed() -> RMS2D_VertexProperties:
    var _new = RMS2D_VertexProperties.new()
    _new.texture_idx = texture_idx
    _new.flip = flip
    _new.width = width
    return _new
