# cashed_items_popup.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charlie Whitfield
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
class_name IVCachedItemsPopup
extends PopupPanel
const SCENE := "res://addons/ivoyager_core/gui_popups/cached_items_popup.tscn"

# Abstract base class for user interface with cached items. I, Voyager
# subclasses: IVOptionsPopup, IVHotkeysPopup.

var stop_sim := true
var layout: Array[Array] # subclass sets in _init()

var _blocking_windows: Array[Window] = IVGlobal.blocking_windows
var _header_left: MarginContainer
var _header_label: Label
var _header_right: MarginContainer
var _content_container: HBoxContainer
var _cancel: Button
var _confirm_changes: Button
var _restore_defaults: Button
var _allow_close := false



func _ready() -> void:
	IVGlobal.close_all_admin_popups_requested.connect(hide)
	close_requested.connect(_on_close_requested)
	popup_hide.connect(_on_popup_hide)
	exclusive = false # Godot ISSUE? not editable in scene?
	_header_left = $VBox/TopHBox/HeaderLeft
	_header_label = $VBox/TopHBox/HeaderLabel
	_header_right = $VBox/TopHBox/HeaderRight
	_content_container = $VBox/Content
	_cancel = $VBox/BottomHBox/Cancel
	_confirm_changes = $VBox/BottomHBox/ConfirmChanges
	_restore_defaults = $VBox/BottomHBox/RestoreDefaults
	_cancel.pressed.connect(_on_cancel)
	_restore_defaults.pressed.connect(_on_restore_defaults)
	_confirm_changes.pressed.connect(_on_confirm_changes)
	_blocking_windows.append(self)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		set_input_as_handled()
		_on_cancel()


# public

func open() -> void:
	if visible:
		return
	if _is_blocking_popup():
		return
	if stop_sim:
		IVGlobal.sim_stop_required.emit(self)
	_build_content()
	size = Vector2i.ZERO
	popup_centered()


func add_subpanel(subpanel_dict: Dictionary, to_column: int, to_row := 999) -> void:
	# See example subpanel_dict formats in IVOptionsPopup or IVHotkeysPopup.
	# Set to_column and/or to_row arbitrarily large to move to end.
	if to_column >= layout.size():
		to_column = layout.size()
		layout.append([])
	var column_array: Array[Dictionary] = layout[to_column]
	if to_row >= column_array.size():
		to_row = column_array.size()
	column_array.insert(to_row, subpanel_dict)


func remove_subpanel(header: StringName) -> Dictionary:
	for column_array in layout:
		var dict_index := 0
		while dict_index < column_array.size():
			var subpanel_dict: Dictionary = column_array[dict_index]
			if subpanel_dict.header == header:
				column_array.remove_at(dict_index)
				return subpanel_dict
			dict_index += 1
	print("Could not find subpanel with header ", header)
	return {}


func move_subpanel(header: StringName, to_column: int, to_row: int) -> void:
	# to_column and/or to_row can be arbitrarily big to move to end
	var subpanel_dict := remove_subpanel(header)
	if subpanel_dict:
		add_subpanel(subpanel_dict, to_column, to_row)


func add_item(item: StringName, setting_label_str: StringName, header: StringName, at_index := 999
		) -> void:
	# use add_subpanel() instead if subpanel doesn't exist already.
	assert(item != "header")
	for column_array in layout:
		var dict_index := 0
		while dict_index < column_array.size():
			var subpanel_dict: Dictionary = column_array[dict_index]
			if subpanel_dict.header == header:
				if at_index >= subpanel_dict.size() - 1:
					subpanel_dict[item] = setting_label_str
					return
				# Dictionaries are ordered but there is no insert!
				var new_subpanel_dict := {}
				var index := 0
				for key: StringName in subpanel_dict:
					new_subpanel_dict[key] = subpanel_dict[key] # 1st is header
					if index == at_index:
						new_subpanel_dict[item] = setting_label_str
					index += 1
				column_array[dict_index] = new_subpanel_dict
				return
			dict_index += 1
	print("Could not find Options subpanel with header ", header)


func remove_item(item: StringName) -> void:
	assert(item != "header")
	for column_array in layout:
		var dict_index := 0
		while dict_index < column_array.size():
			var subpanel_dict: Dictionary = column_array[dict_index]
			subpanel_dict.erase(item)
			if subpanel_dict.size() == 1: # only header remains
				column_array.remove_at(dict_index)
				dict_index -= 1
			dict_index += 1


# private

func _build_content() -> void:
	for child in _content_container.get_children():
		_content_container.remove_child(child)
		child.queue_free()
	for column_array in layout:
		var column_vbox := VBoxContainer.new()
		_content_container.add_child(column_vbox)
		for subpanel_dict: Dictionary in column_array:
			var subpanel_container := PanelContainer.new()
			column_vbox.add_child(subpanel_container)
			var subpanel_vbox := VBoxContainer.new()
			subpanel_container.add_child(subpanel_vbox)
			var header_label := Label.new()
			subpanel_vbox.add_child(header_label)
			header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			header_label.text = subpanel_dict.header
			for item: StringName in subpanel_dict:
				if item != &"header":
					var label_name: StringName = subpanel_dict[item]
					var setting_hbox := _build_item(item, label_name)
					subpanel_vbox.add_child(setting_hbox)
	_on_content_built()


func _build_item(_item: StringName, _item_label_str: StringName) -> HBoxContainer:
	# subclass must override!
	return HBoxContainer.new()


func _on_content_built() -> void:
	# subclass logic
	pass


func _on_restore_defaults() -> void:
	# subclass logic
	_build_content.call_deferred()


func _on_confirm_changes() -> void:
	# subclass logic
	_allow_close = true
	hide()


func _on_cancel() -> void:
	# subclass logic
	_allow_close = true
	hide()


func _on_popup_hide() -> void:
	if !_allow_close:
		show.call_deferred()
		return
	_allow_close = false
	for child in _content_container.get_children():
		_content_container.remove_child(child)
		child.queue_free()
	if stop_sim:
		IVGlobal.sim_run_allowed.emit(self)


func _on_close_requested() -> void:
	# TODO Godot 4.1.1 ISSUE: This is basically useless. It is only called if
	# exclusive == false and root viewport gui_embed_subwindows == false.
	# But we want to keep gui_embed_subwindows == true.
	# Also, hide() is done by the engine, contrary to docs.
	# If this is fixed we can remove the '_allow_close' hack.
	print("close_requested signal works now! Use requirements were prohibitive in Godot 4.1.1")


func _is_blocking_popup() -> bool:
	for window in _blocking_windows:
		if window.visible:
			return true
	return false

