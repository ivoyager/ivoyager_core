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
## Maintains correct anchor position for Controls that resize for any reason
##
## Set desired minimum size for each "gui_size" setting in [member sizes].
## Implementation differs
## depending on Container context (see below). In either case, the Control will
## expand beyond specified [member sizes] to fit contents.[br][br]
##
## If parent Control is in a Container, this node sets [member Control.custom_minimum_size].
## For resize to happen, container sizing properties must be set to a "shrink"
## value. There is no repositioning for a Control in a Container.[br][br]
##
## If parent Control is [u]not[/u] in a Container, this node sets [member Control.size]
## and repositions to anchors after a resize happens for any reason (e.g., due
## to content change). In this context, this node may be useful for maintaining
## minimum size and correct screen position even if Control is intended only to
## fit contents (if this is the case, leave all [member sizes] elements as
## default Vector2.ZERO).




## Control size for each setting of [enum IVGlobal.GUISize]. The array size must
## match the enum size. Default array elements are all Vector2.ZERO, which will
## result in the Control resizing to fit contents. 
@export var sizes: Array[Vector2] = [
	Vector2.ZERO, # GUI_SMALL
	Vector2.ZERO, # GUI_MEDIUM
	Vector2.ZERO, # GUI_LARGE
]
## Not used if Control is in a Container. Frame delay before Control is resized
## a second time and then repositioned. Complex Control scene trees may require
## a value >0 for correct resizing and repositioning when child Controls are
## resizing for some reason (e.g., due to font resing). Set to 0 to skip the
## delay and the second resize.
@export var resize_again_delay := 3


var _is_in_container: bool
var _suppress_resize := false


@onready var _settings := IVGlobal.settings
@onready var _control := get_parent() as Control



func _ready() -> void:
	assert(sizes.size() == IVGlobal.GUISize.size())
	assert(_control, "IVControlResizer requires a Control as parent")
	IVGlobal.setting_changed.connect(_settings_listener)
	IVGlobal.simulator_started.connect(_resize)
	_control.resized.connect(_resize)
	_is_in_container = _control.get_parent() is Container
	_resize()


func _resize() -> void:
	if _suppress_resize:
		return # bail out if recursion or during resize_again_delay
	_suppress_resize = true
	
	var gui_size: int = _settings[&"gui_size"]
	var size := sizes[gui_size]
	
	if _is_in_container:
		_control.custom_minimum_size = size
		_suppress_resize = false
		return
	
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


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"gui_size":
		_resize()
