# nav_button.gd
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
class_name IVNavButton
extends Button

## Button widget that provides user selection of an [IVBody]
##
## The widget is a flat toggle Button that is in the pressed state when the body
## is selected. The pressed state has a theme override outline. The child
## TextureRect fits within the button keeping aspect. (Note: TextureButton
## doesn't allow theming of the button, hence the more complicated
## Button/TextureRect construction.)[br][br]
##
## The button is set to fill and expand by default, which works well, e.g.,
## in a [IVNavButtonsBox]. It has a tiny default [param custom_minimum_size]
## mainly for debugging purposes (so it will have a tiny but visible size if
## the container sizing isn't correct).

const SCENE := "res://addons/ivoyager_core/gui_widgets/nav_button.tscn"

## E.g., "PLANET_EARTH", "MOON_EUROPA", etc.
@export var body_name: StringName
## If true, use [member IVBody.texture_slice_2d] instead of [member
## IVBody.texture_2d]. This is the non-square "slice" of the Sun (or
## possibly other stars). Also changes texture expand and stretch modes.
@export var use_texture_slice := false
## If set, the currently selected body button will grab focus on sim start.
@export var focus_selected_on_sim_start := false


var _body: IVBody
var _selection_manager: IVSelectionManager

@onready var _texture_rect: TextureRect = $TextureRect


## Creates and returns an [IVNavButton] instance. The button will be configured
## (connected to [IVBody] and given a texture) [i]after[/i] the button is added or
## the system is built, whichever comes later. If the button can't find its
## corresponding [IVBody], it will generate a warning message.[br][br]
@warning_ignore("shadowed_variable", "shadowed_variable_base_class")
static func create(body_name: StringName, use_texture_slice := false, 
		focus_selected_on_sim_start := false, custom_minimum_size := Vector2(10, 10)
		) -> IVNavButton:
	# Godot 4.5.1 ISSUE?: preload below causes editor start error spam
	# referencing tscn line: 'script = ExtResource("xxxxxx")'. Circular ref?
	var button: IVNavButton = (load(SCENE) as PackedScene).instantiate()
	button.body_name = body_name
	button.use_texture_slice = use_texture_slice
	button.focus_selected_on_sim_start = focus_selected_on_sim_start
	button.custom_minimum_size = custom_minimum_size
	return button


func _ready() -> void:
	IVGlobal.system_tree_built_or_loaded.connect(_configure)
	IVGlobal.simulator_started.connect(_on_sim_started)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	
	
	
	#IVGlobal.update_gui_requested.connect(_update_selection)
	set_default_cursor_shape(CURSOR_POINTING_HAND)
	if IVGlobal.state[&"is_system_built"]:
		_configure()


func _pressed() -> void:
	_selection_manager.select_body(_body)


func _on_sim_started() -> void:
	_update_selection()
	if focus_selected_on_sim_start and button_pressed:
		grab_focus()


func _configure(_dummy := false) -> void:
	if use_texture_slice:
		_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
	_body = IVBody.bodies.get(body_name)
	if !_body:
		push_warning("Did not find IVBody with name '%s'" % body_name)
		disabled = true
		return
	
	tooltip_text = _body.name
	if use_texture_slice:
		_texture_rect.texture = _body.texture_slice_2d
	else:
		_texture_rect.texture = _body.texture_2d
	
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	_selection_manager.selection_changed.connect(_update_selection)
	_selection_manager.selection_reselected.connect(_update_selection)


func _clear_procedural() -> void:
	_body = null
	_texture_rect.texture = null # looks better during quit deconstruction...
	if _selection_manager:
		_selection_manager.selection_changed.disconnect(_update_selection)
		_selection_manager.selection_reselected.disconnect(_update_selection)
		_selection_manager = null


func _update_selection(_dummy := false) -> void:
	button_pressed = _selection_manager.get_body() == _body
