# body_position_visual.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
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
class_name IVBodyPositionVisual
extends Sprite3D

## Visual symbol and/or name of an [IVBody] in the 3D world.
##
## This node is the symbol: a billboarded, screen-fixed [Sprite3D] textured from
## the symbol atlas (see [IVSymbolTextures]) and tinted by the group color. Its
## child [Label3D] is the name. Symbol and name visibilities are independent
## ([IVBodyHUDsState]); when both show, the name sits to the right of and
## slightly above the centered symbol, otherwise the name is centered on the
## body. Symbol shape and color are per group, shared with the body's orbit.[br][br]
##
## Symbol screen size and name font size both follow [IVThemeManager] (the
## "body_symbol_size_percent" and "label3d_names_size_percent" settings).


## Name-label offset from the centered symbol when both are shown, as a fraction
## of the symbol's screen size ([code]x[/code] rightward, positive [code]y[/code]
## up). Project-wide; set before [IVBody]s are built for a uniform effect. (It is
## read on each HUD update, so a later change applies to a given body only on its
## next symbol/name/size/visibility update.)
static var name_offset_ratio := Vector2(0.7, 0.3)


var _body: IVBody
var _body_huds_state: IVBodyHUDsState = IVGlobal.program[&"BodyHUDsState"]
var _name_label: Label3D

# set on _ready() and changed signals
var _names_visible: bool
var _symbols_visible: bool
var _body_huds_visible: bool # this body (e.g., too close / too far)
var _symbol_type := 0 # IVGlobal.Symbols
var _color := Color.WHITE
var _name_font_size: int
var _symbol_size: float
var _camera_fov: float
var _viewport_size: Vector2


func _init(body: IVBody) -> void:
	_body = body
	name = &"BodyPositionVisual"
	_name_label = Label3D.new()
	_name_label.name = &"NameLabel"
	add_child(_name_label)


func _ready() -> void:
	IVGlobal.camera_fov_changed.connect(_on_camera_fov_changed)
	IVGlobal.viewport_size_changed.connect(_on_viewport_size_changed)
	_body_huds_state.visibility_changed.connect(_set_global_visibilities)
	_body_huds_state.color_changed.connect(_set_color)
	_body_huds_state.symbol_changed.connect(_set_symbol)
	_body.huds_visibility_changed.connect(_on_body_huds_changed)
	_body_huds_visible = _body.huds_visible
	_symbol_type = _body_huds_state.get_symbol_type(_body.flags)
	_color = _body_huds_state.get_color(_body.flags)

	var theme_manager: IVThemeManager = IVGlobal.program[&"ThemeManager"]
	_name_font_size = theme_manager.get_label3d_names_font_size()
	_symbol_size = theme_manager.get_body_symbol_size()
	theme_manager.label3d_font_size_changed.connect(_on_name_font_size_changed)
	theme_manager.body_symbol_size_changed.connect(_on_body_symbol_size_changed)

	# self = symbol sprite
	billboard = StandardMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	modulate = _color

	# name label child
	_name_label.font = theme_manager.get_main_font()
	_name_label.billboard = StandardMaterial3D.BILLBOARD_ENABLED
	_name_label.fixed_size = true
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.modulate = _color

	var viewport := get_viewport()
	_camera_fov = viewport.get_camera_3d().fov
	_viewport_size = viewport.get_visible_rect().size

	_set_global_visibilities()


func _set_global_visibilities() -> void:
	_names_visible = _body_huds_state.is_name_visible(_body.flags)
	_symbols_visible = _body_huds_state.is_symbol_visible(_body.flags)
	_set_visual_state()


func _set_visual_state() -> void:
	var show_symbol := _body_huds_visible and _symbols_visible and _symbol_type >= 0
	var show_name := _body_huds_visible and _names_visible
	if !show_symbol and !show_name:
		visible = false
		return
	visible = true
	texture = IVSymbolTextures.get_atlas_texture(_symbol_type) if show_symbol else null
	_name_label.visible = show_name
	if show_name:
		_name_label.text = _body.get_hud_name()
		_name_label.font_size = _name_font_size
	_update_name_offset(show_symbol)
	_update_pixel_sizes()


# Name centered on the body, or offset per [member name_offset_ratio] (times the
# symbol screen size) when the symbol also shows. Label3D offset is in screen px
# because the name pixel_size makes 1 unit ~= 1 px.
func _update_name_offset(show_symbol: bool) -> void:
	if show_symbol:
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_name_label.offset = name_offset_ratio * _symbol_size
	else:
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.offset = Vector2.ZERO


# Screen-fixed sizing: the name label renders font_size ~= screen px; the symbol
# sprite renders its atlas cell at _symbol_size screen px.
func _update_pixel_sizes() -> void:
	# Godot errors if fov set > 179, so tan() won't go to INF here...
	var factor := 2.0 * tan(deg_to_rad(_camera_fov) * 0.5) / _viewport_size.y
	_name_label.pixel_size = factor
	if texture:
		pixel_size = factor * _symbol_size / float(texture.get_height())


func _set_color() -> void:
	var color := _body_huds_state.get_color(_body.flags)
	if _color == color:
		return
	_color = color
	modulate = color
	_name_label.modulate = color


func _set_symbol() -> void:
	var symbol_type := _body_huds_state.get_symbol_type(_body.flags)
	if _symbol_type == symbol_type:
		return
	_symbol_type = symbol_type
	_set_visual_state() # updates texture, offset and sizes if the symbol shows


func _on_body_huds_changed(huds_visible: bool) -> void:
	if _body_huds_visible == huds_visible:
		return
	_body_huds_visible = huds_visible
	_set_visual_state()


func _on_name_font_size_changed(name_size: int) -> void:
	if _name_font_size == name_size:
		return
	_name_font_size = name_size
	if _name_label.visible:
		_name_label.font_size = _name_font_size


func _on_camera_fov_changed(fov: float) -> void:
	if _camera_fov == fov:
		return
	_camera_fov = fov
	_update_pixel_sizes()


func _on_viewport_size_changed(size: Vector2) -> void:
	if _viewport_size == size:
		return
	_viewport_size = size
	_update_pixel_sizes()


func _on_body_symbol_size_changed(symbol_size: float) -> void:
	if _symbol_size == symbol_size:
		return
	_symbol_size = symbol_size
	_set_visual_state()
