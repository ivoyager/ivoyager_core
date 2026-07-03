# huds_box.gd
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
class_name IVHUDsBox
extends VBoxContainer

## A BoxContainer widget that has all user interface for HUDs
##
## To enable wiki link labels ([IVLinkLabel]) instead of plain [Label]s for each
## row, set [member enable_wiki_links] to true. [IVWikiManager] must also be
## added in [IVCoreInitializer].

## Theme type variation used by [IVHUDsFoldable] decendents. If &"" (default),
## the foldable widgets will keep looking up the Node tree for this "tree
## property". The property is set in [IVTopUI] for a global GUI value.
@export var foldables_theme_type_variation := &""


# Header-row shortcut SpinBoxes, each two-way bound to an IVSettingsManager
# "size" setting (also settable in IVOptionsPopup). Keyed by setting for the
# reverse (setting-changed -> SpinBox) update.
var _setting_spinboxes: Dictionary[StringName, SpinBox] = {}

@onready var _names_size_spinbox: SpinBox = $BodiesHeaders/Names/SpinBox
@onready var _body_symbol_size_spinbox: SpinBox = $BodiesHeaders/Symbols/SpinBox
@onready var _point_size_spinbox: SpinBox = $SBGsHeaders/Points/SpinBox
@onready var _sbg_symbol_size_spinbox: SpinBox = $SBGsHeaders/Symbols/SpinBox



func _ready() -> void:
	# Settings aren't valid until core init; GUI _ready() runs before that.
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	_init_setting_spinbox(_names_size_spinbox, &"label3d_names_size_percent")
	_init_setting_spinbox(_body_symbol_size_spinbox, &"body_symbol_size_percent")
	_init_setting_spinbox(_point_size_spinbox, &"small_bodies_point_size")
	_init_setting_spinbox(_sbg_symbol_size_spinbox, &"small_bodies_symbol_size_percent")
	IVSettingsManager.changed.connect(_on_setting_changed)


func _init_setting_spinbox(spinbox: SpinBox, setting: StringName) -> void:
	_setting_spinboxes[setting] = spinbox
	var value: int = IVSettingsManager.get_setting(setting)
	spinbox.set_value_no_signal(value)
	var line_edit := spinbox.get_line_edit()
	line_edit.context_menu_enabled = false
	line_edit.expand_to_text_length = true
	line_edit.add_theme_constant_override(&"minimum_character_width", 1)
	spinbox.value_changed.connect(_on_spinbox_value_changed.bind(setting))


func _on_spinbox_value_changed(value: float, setting: StringName) -> void:
	IVSettingsManager.change_setting(setting, int(value))


func _on_setting_changed(setting: StringName, value: Variant) -> void:
	if !_setting_spinboxes.has(setting):
		return
	var spinbox := _setting_spinboxes[setting]
	var int_value: int = value
	spinbox.set_value_no_signal(int_value)
