# control_mod_resizable.gd
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
class_name IVControlModResizable
extends Node

## Resizes parent Control to specified sizes with changes in setting "gui_size".
## Maintains correct anchor position for Controls (not in a Container) that
## resize for any reason
##
## Set either [member base_size] or [member sizes], or leave both as
## default for the repositioning functionality only. Implementation differs
## depending on Container context (see below). In either case, the Control will
## expand beyond specified sizes to fit contents.[br][br]
##
## If parent Control is in a Container, this node sets [member Control.custom_minimum_size].
## For resize to happen, container sizing properties must be set to a "shrink"
## value. There is no repositioning for a Control in a Container.[br][br]
##
## If parent Control is [u]not[/u] in a Container, this node sets [member Control.size]
## and repositions to anchors after a resize happens for any reason (e.g., due
## to content change). In this context, this node is useful for maintaining
## minimum size and correct screen position even if Control is intended only to
## fit contents (if this is the case, leave [member base_size] and [member sizes]
## as default values).[br][br]
##
## Also for parent Control not in a Container, a negative value for x or y means
## "Don't resize!" in this axis. This is differant than 0.0, where size is set
## to 0.0 but imediately resets to fit content. Use this for a Control that sets
## its own size by code in one or both axis.


## Set only [member base_size] or [member sizes].
## Base Control size multiplied by [member IVCoreSettings.gui_size_multipliers]
## for each [enum IVGlobal.GUISize]. If set, the resulting sizes will overwrite
## values in [member sizes]. A negative x or y means "Don't resize!" in this
## axis (for Control not in a Container only).
@export var base_size := Vector2.ZERO
## Set only [member base_size] or [member sizes].
## Control size for each setting of [enum IVGlobal.GUISize]. If
## [member base_size] is set, this array will be filled (overwritten) using
## [member base_size] × [member IVCoreSettings.gui_size_multipliers]. A negative
## x or y means "Don't resize!" in this axis (for Control not in a Container only).
@export var sizes: Array[Vector2] = []
## Not used if Control is in a Container. Frame delay before Control is resized
## a second time and then repositioned. Complex Control scene trees may require
## a value >0 for correct resizing and repositioning when child Controls are
## resizing for some reason (some widgets have a frame delay for their own
## resizing). Set to 0 to skip the delay and the second resize.
@export var resize_again_delay := 1
## Not used if Control is in a Container. This setting might be useful for a
## PanelContainer that shares the screen with other PanelContainers and has a
## large vertical scroll. If value is 0.0 or greater, it indicates that the
## parent Control should be truncated at the bottom to maintain the given
## space between it and any other PanelContainer below. The other PanelContainer
## must have the same parent control.
@export var panel_under_spacing := -1.0


var _in_container: bool
var _suppress_resize := false


@onready var _control := get_parent() as Control


func _ready() -> void:
	if IVStateManager.is_core_inited:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	assert(_control, "IVControlModResizable requires a Control as parent")
	IVSettingsManager.changed.connect(_settings_listener)
	IVStateManager.simulator_started.connect(_resize)
	_control.resized.connect(_resize) # code suppresses recursion
	_in_container = _control.get_parent() is Container
	if base_size and sizes:
		push_warning("Provided 'sizes' are overwritten using 'base_size'. Set only one of these!")
	var n_sizes := IVGlobal.GUISize.size()
	if base_size:
		assert(!_in_container or (base_size.x >= 0.0 and base_size.y >= 0.0),
				"Negative size allowed only for Control not in a Container")
		var multipliers := IVCoreSettings.gui_size_multipliers
		sizes.resize(n_sizes)
		for i in n_sizes:
			# negative x or y has qualitative meaning (don't resize!)
			sizes[i].x = roundf(base_size.x * multipliers[i]) if base_size.x >= 0.0 else -1.0
			sizes[i].y = roundf(base_size.y * multipliers[i]) if base_size.y >= 0.0 else -1.0
	elif sizes:
		assert(sizes.size() == n_sizes, "'sizes' size does not match enum 'IVGlobal.GUISize' size")
		if _in_container:
			for i in n_sizes:
				assert(sizes[i].x >= 0.0 and sizes[i].y >= 0.0,
						"Negative size allowed only for Control not in a Container")
	else:
		sizes.resize(n_sizes)
	_resize()


func _resize() -> void:
	if _suppress_resize:
		return
	_suppress_resize = true
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	var size := sizes[gui_size]
	
	if _in_container:
		_control.custom_minimum_size = size
		_suppress_resize = false
		return
	
	# All below NOT in a Container...
	
	if size.x < 0.0: # don't resize this axis!
		size.x = _control.size.x
	if size.y < 0.0:
		size.y = _control.size.y
	_control.size = size
	if resize_again_delay:
		for i in resize_again_delay:
			await get_tree().process_frame
		_control.size = size
	await get_tree().process_frame
	var viewport_size := get_viewport().get_visible_rect().size
	_control.position.x = _control.anchor_left * (viewport_size.x - _control.size.x)
	_control.position.y = _control.anchor_top * (viewport_size.y - _control.size.y)
	_suppress_resize = false
	_panel_under_truncate()


func _panel_under_truncate() -> void:
	if panel_under_spacing < 0.0:
		return
	_suppress_resize = true
	var height := _control.size.y
	var new_height := height
	var rect := _control.get_rect()
	rect.size += Vector2(0.0, panel_under_spacing)
	for child in _control.get_parent_control().get_children():
		var panel_container := child as PanelContainer
		if !panel_container or panel_container == _control:
			continue
		var other_rect := panel_container.get_rect()
		if !rect.intersects(other_rect):
			continue
		var other_top := other_rect.position.y
		if other_top < rect.position.y + panel_under_spacing:
			continue # can't fix this
		var height_limit := other_top - _control.position.y - panel_under_spacing
		if height_limit < new_height:
			new_height = height_limit
	if new_height < height:
		_control.size.y = new_height
	_suppress_resize = false


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"gui_size":
		_resize()
