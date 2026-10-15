# control_mod_scroll_share.gd
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
class_name IVControlModScrollShare
extends Node

## Caps parent [ScrollContainer]'s height to the share of its [VBoxContainer]
## that the box's other children leave
##
## Add as a child of a ScrollContainer with vertical scroll mode
## [constant ScrollContainer.SCROLL_MODE_MAXIMIZE_FIRST] that shares a
## height-capped VBoxContainer with children that must stay in view (e.g., a
## button row below a scrolling list in a panel that [IVEdgeContainer] caps).
## Without it, Godot hands the scroll the box's whole maximum height, so it
## fits all its content and squeezes the other children out.[br][br]
##
## Hazard: this node sets the height of the ScrollContainer's
## [member Control.custom_maximum_size], replacing any set there.


var _scroll: ScrollContainer
var _box: VBoxContainer


func _ready() -> void:
	_scroll = get_parent()
	_box = _scroll.get_parent()
	assert(_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_MAXIMIZE_FIRST,
			"IVControlModScrollShare requires vertical_scroll_mode MAXIMIZE_FIRST")
	_box.maximum_size_changed.connect(_update_maximum_height)
	_box.child_entered_tree.connect(_on_box_child_entered_tree)
	for child in _box.get_children():
		_on_box_child_entered_tree(child)
	_update_maximum_height()


func _update_maximum_height() -> void:
	var box_maximum_height := _box.get_combined_maximum_size().y
	var maximum_height := -1.0
	if box_maximum_height >= 0.0:
		var others_height := 0.0
		for child in _box.get_children():
			if child == _scroll or not child is Control:
				continue
			var control: Control = child
			if !control.visible or control.top_level:
				continue
			others_height += control.get_combined_minimum_size().y
			others_height += _box.get_theme_constant(&"separation")
		maximum_height = maxf(box_maximum_height - others_height, 0.0)
	if _scroll.custom_maximum_size.y == maximum_height:
		return
	_scroll.custom_maximum_size = Vector2(_scroll.custom_maximum_size.x, maximum_height)


func _on_box_child_entered_tree(child: Node) -> void:
	if child == _scroll or not child is Control:
		return
	var control: Control = child
	control.minimum_size_changed.connect(_update_maximum_height)
	control.visibility_changed.connect(_update_maximum_height)
