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

## Visual text name or symbol of an [IVBody] instance.

var _color: Color
var _use_orbit_color: bool

var _body_huds_state: IVBodyHUDsState = IVGlobal.program[&"BodyHUDsState"]
var _body: IVBody
var _name_font: Font
var _symbol_font: Font
var _names_visible := false
var _symbols_visible := false
var _body_huds_visible := false # too close / too far



func _init(body: IVBody, color := Color.WHITE, use_orbit_color := false) -> void:
	_body = body
	_color = color
	_use_orbit_color = use_orbit_color
	_name_font = IVGlobal.fonts[&"hud_names"]
	_symbol_font = IVGlobal.fonts[&"hud_symbols"]
	name = &"BodyLabel"


func _ready() -> void:
	_body_huds_state.visibility_changed.connect(_on_global_huds_changed)
	_body.huds_visibility_changed.connect(_on_body_huds_changed)
	if _use_orbit_color:
		_body_huds_state.color_changed.connect(_set_color)
	else:
		modulate = _color
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	billboard = StandardMaterial3D.BILLBOARD_ENABLED
	
	fixed_size = true
	pixel_size = 0.0006 # FIXME: Check this!
	
	_body_huds_visible = _body.huds_visible
	_on_global_huds_changed()



func _on_global_huds_changed() -> void:
	_names_visible = _body_huds_state.is_name_visible(_body.flags)
	_symbols_visible = !_names_visible and _body_huds_state.is_symbol_visible(_body.flags)
	_set_visual_state()


func _on_body_huds_changed(is_visible_: bool) -> void:
	_body_huds_visible = is_visible_
	_set_visual_state()


func _set_visual_state() -> void:
	if !_body_huds_visible:
		visible = false
		return
	if _names_visible:
		text = _body.get_hud_name()
		font = _name_font
		visible = true
	elif _symbols_visible:
		text = _body.get_symbol()
		font = _symbol_font
		visible = true
	else:
		visible = false


func _set_color() -> void:
	# only connected if _use_orbit_color == true at init
	var color := _body_huds_state.get_orbit_color(_body.flags)
	if _color == color:
		return
	_color = color
	modulate = color
