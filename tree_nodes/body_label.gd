# body_label.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2025 Charlie Whitfield
# I, Voyager is a registered trademark of Charlie Whitfield in the US
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************************
extends Label3D
class_name IVBodyLabel

## Visual name or symbol of an [IVBody] instance in the 3D world.

# init
var _body: IVBody
var _color: Color
var _use_orbit_color: bool
var _body_huds_state: IVBodyHUDsState = IVGlobal.program[&"BodyHUDsState"]

# set on _ready() and changed signals
var _names_visible: bool # global
var _symbols_visible: bool # global
var _body_huds_visible: bool # this body (e.g., too close / too far)
var _names_font_size: int
var _symbols_font_size: int
var _camera_fov: float
var _viewport_size: Vector2




func _init(body: IVBody, color := Color.WHITE, use_orbit_color := false) -> void:
	_body = body
	_color = color
	_use_orbit_color = use_orbit_color
	name = &"BodyLabel"


func _ready() -> void:
	IVGlobal.camera_fov_changed.connect(_on_camera_fov_changed)
	IVGlobal.viewport_size_changed.connect(_on_viewport_size_changed)
	_body_huds_state.visibility_changed.connect(_set_global_visibilities)
	if _use_orbit_color:
		_body_huds_state.color_changed.connect(_set_color)
	else:
		modulate = _color
	_body.huds_visibility_changed.connect(_on_body_huds_changed)
	_body_huds_visible = _body.huds_visible
	
	var theme_manager: IVThemeManager = IVGlobal.program[&"ThemeManager"]
	font = theme_manager.get_main_font()
	_names_font_size = theme_manager.get_label3d_names_font_size()
	_symbols_font_size = theme_manager.get_label3d_symbols_font_size()
	theme_manager.label3d_font_size_changed.connect(_on_font_size_changed)
	
	var viewport := get_viewport()
	_camera_fov = viewport.get_camera_3d().fov
	_viewport_size = viewport.get_visible_rect().size
	
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	billboard = StandardMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	_set_pixel_size()
	_set_global_visibilities()


func _set_pixel_size() -> void:
	const PIXEL_MULTIPLIER := 2.0
	# Godot errors if fov set > 179, so tan() won't go to INF here...
	pixel_size = PIXEL_MULTIPLIER * tan(deg_to_rad(_camera_fov) * 0.5) / _viewport_size.y


func _set_global_visibilities() -> void:
	_names_visible = _body_huds_state.is_name_visible(_body.flags)
	_symbols_visible = !_names_visible and _body_huds_state.is_symbol_visible(_body.flags)
	_set_visual_state()


func _set_visual_state() -> void:
	if !_body_huds_visible:
		hide()
		return
	if _names_visible:
		text = _body.get_hud_name()
		font_size = _names_font_size
		show()
	elif _symbols_visible:
		text = _body.get_symbol()
		font_size = _symbols_font_size
		show()
	else:
		hide()


func _set_color() -> void:
	# only connected if _use_orbit_color == true at init
	var color := _body_huds_state.get_orbit_color(_body.flags)
	if _color == color:
		return
	_color = color
	modulate = color


func _on_camera_fov_changed(fov: float) -> void:
	if _camera_fov == fov:
		return
	_camera_fov = fov
	_set_pixel_size()


func _on_viewport_size_changed(size: Vector2) -> void:
	if _viewport_size == size:
		return
	_viewport_size = size
	_set_pixel_size()


func _on_body_huds_changed(huds_visible: bool) -> void:
	if _body_huds_visible == huds_visible:
		return
	_body_huds_visible = huds_visible
	_set_visual_state()


func _on_font_size_changed(name_size: int, symbol_size: int) -> void:
	if _names_font_size == name_size and _symbols_font_size == symbol_size:
		return
	_names_font_size = name_size
	_symbols_font_size = symbol_size
	_set_visual_state()
