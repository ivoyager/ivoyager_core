# control_mod_spacing.gd
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
class_name IVControlModSpacing
extends Node

## Scales parent Control's theme constant overrides with changes in setting
## "gui_size"
##
## Add as a child of a Control whose [code]theme_override_constants[/code] (a
## MarginContainer's margins, a BoxContainer's separation) should keep their
## proportion to the text, as the theme's own spacing does under
## [IVThemeManager]. The overrides the parent has when this node is ready are its
## GUI_LARGE size, the size [member IVCoreSettings.gui_size_multipliers]
## multiply, and only those named in [member IVThemeManager.pixel_constants] are
## scaled. An override the parent sets after that is replaced at the next
## "gui_size" change.[br][br]
##
## See also [IVControlModResizable].


var _base_constants: Dictionary[StringName, int] = {}


@onready var _control := get_parent() as Control



func _ready() -> void:
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	assert(_control, "IVControlModSpacing requires a Control as parent")
	IVSettingsManager.changed.connect(_settings_listener)
	# A Control lists its overrides only as properties, one per theme constant its class has.
	const OVERRIDE_PREFIX := "theme_override_constants/"
	for property in _control.get_property_list():
		var property_name: String = property[&"name"]
		if !property_name.begins_with(OVERRIDE_PREFIX):
			continue
		var constant_name := StringName(property_name.trim_prefix(OVERRIDE_PREFIX))
		if (_control.has_theme_constant_override(constant_name)
				and IVThemeManager.pixel_constants.has(constant_name)):
			_base_constants[constant_name] = _control.get_theme_constant(constant_name)
	_scale_constants()


func _scale_constants() -> void:
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
	_control.begin_bulk_theme_override()
	for constant_name in _base_constants:
		var base_constant := _base_constants[constant_name]
		_control.add_theme_constant_override(constant_name, roundi(base_constant * multiplier))
	_control.end_bulk_theme_override()


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"gui_size":
		_scale_constants()
