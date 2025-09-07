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

var _color: Color
var _use_orbit_color: bool

var _body_huds_state: IVBodyHUDsState = IVGlobal.program[&"BodyHUDsState"]
var _body: IVBody
var _names_visible := false
var _symbols_visible := false
var _body_huds_visible := false # too close / too far

var _names_font_size := 16 # will change w/ global signal update_gui_requested
var _symbols_font_size := 16 # as above



func _init(body: IVBody, color := Color.WHITE, use_orbit_color := false) -> void:
	_body = body
	_color = color
	_use_orbit_color = use_orbit_color
	name = &"BodyLabel"


func _ready() -> void:
	_body_huds_state.visibility_changed.connect(_on_global_huds_changed)
	if _use_orbit_color:
		_body_huds_state.color_changed.connect(_set_color)
	else:
		modulate = _color
	_body.huds_visibility_changed.connect(_on_body_huds_changed)
	_body_huds_visible = _body.huds_visible
	var theme_manager: IVThemeManager = IVGlobal.program[&"ThemeManager"]
	font = theme_manager.get_main_font()
	theme_manager.label3d_font_size_changed.connect(_on_font_size_changed)
	
	pixel_size = 0.0007 # FIXME: This needs to change with camera fov...
	
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	billboard = StandardMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	_on_global_huds_changed()


func _on_global_huds_changed() -> void:
	_names_visible = _body_huds_state.is_name_visible(_body.flags)
	_symbols_visible = !_names_visible and _body_huds_state.is_symbol_visible(_body.flags)
	_set_visual_state()


func _on_body_huds_changed(is_visible_: bool) -> void:
	_body_huds_visible = is_visible_
	_set_visual_state()


func _on_font_size_changed(name_size: int, symbol_size: int) -> void:
	_names_font_size = name_size
	_symbols_font_size = symbol_size
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
