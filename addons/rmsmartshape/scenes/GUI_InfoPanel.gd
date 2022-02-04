@tool
extends PanelContainer

@export_node_path var p_lbl_idx
@export_node_path var p_lbl_tex
@export_node_path var p_lbl_width
@export_node_path var p_lbl_flip

func set_idx(i:int):
    get_node(p_lbl_idx).text = "IDX: %s" % i

func set_texture_idx(i:int):
    get_node(p_lbl_tex).text = "Texture2D: %s" % i

func set_width(f:float):
    get_node(p_lbl_width).text = "Width: %s" % f

func set_flip(b:bool):
    get_node(p_lbl_flip).text = "Flip: %s" % b
