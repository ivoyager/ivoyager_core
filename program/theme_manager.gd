# theme_manager.gd
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
class_name IVThemeManager
extends RefCounted

## Modifies the "main" Theme (specified here or by project) and manages dynamic
## font sizing
##
## For dynamic font sizing to work, the project needs a custom theme. That
## might be specifed 
##
## This manager adds custom theme styles that are required by some GUI widgets
## for correct appearence. These theme "mods" can be added to or changed by
## modifying Callables in [member main_theme_mods].[br][br]
##
## For font sizing (dynamic and fixed), several theme type variations are
## are defined and managed: "MediumFont" (dynamic), "LargeFont" (dynamic),
## "MediumFixedFont", and "LargeFixedFont". The main theme's default_font_size
## is also dynamically managed. Font sizes are determined by this class's
## properties and (for dynamic) the global "gui_size" setting (one of
## [enum IVGlobal.GUISize]).[br][br]


## Signal provided for managing Label3D font sizing. Name and symbol sizes are
## the the main theme's default_font_size modified by global settings
## "label3d_names_size_percent" and "label3d_symbols_size_percent", respectively.
signal label3d_font_size_changed(name_size: int, symbol_size: int)


## If set, ignore ProjectSettings/gui/theme/custom and [member fallback_theme_path].
static var override_theme_path := ""
## Fallback theme if [member override_theme_path] and ProjectSettings/gui/theme/custom
## are not set.
static var fallback_theme_path := "res://addons/ivoyager_core/resources/ivoyager_theme.tres"
static var override_font_path := ""
static var fallback_font_path := "res://addons/ivoyager_assets/fonts/Roboto-NotoSansSymbols-merged.ttf"

var set_default_font := true
var main_theme_mods: Array[Callable] = [
	add_gui_font_sizes,
	#add_borderless_color_picker_button,
]

## Value multiplied by [member IVCoreSettings.gui_size_multipliers] for the
## default font.
var default_font_base_size := 16
## Value multiplied by [member IVCoreSettings.gui_size_multipliers] for type
## variation "MediumFont".
var medium_font_base_size := 20
## Value multiplied by [member IVCoreSettings.gui_size_multipliers] for type
## variation "LargeFont".
var large_font_base_size := 24
var medium_font_fixed_size := 20
var large_font_fixed_size := 24


var _main_theme: Theme
var _main_font: Font
var _default_font_sizes: Array[int] = []
var _medium_font_sizes: Array[int] = []
var _large_font_sizes: Array[int] = []


## Returns a [Theme] specified by [member override_theme_path],
## ProjectSettings/GUI/Theme/Custom, or [member fallback_theme_path], in that
## order of precedence.
static func get_main_theme() -> Theme:
	var theme: Theme
	if override_theme_path:
		theme = load(override_theme_path)
		assert(theme, "IVThemeInitializer.override_theme_path is not a valid theme path")
		return theme
	var project_theme_path: String = ProjectSettings.get_setting("gui/theme/custom")
	if project_theme_path:
		theme = load(project_theme_path)
		assert(theme, "ProjectSettings/gui/theme/custom is not a valid theme path")
		return theme
	theme = load(fallback_theme_path)
	assert(theme, "IVThemeInitializer.fallback_theme_path is not a valid theme path")
	return theme


## Returns Font specified by [member override_font_path], ProjectSettings/gui/theme/custom_font,
## or [member fallback_font_path], in that order of precedence.
static func get_main_font() -> Font:
	var main_font: Font
	if override_font_path:
		main_font = load(override_font_path)
		assert(main_font, "IVThemeInitializer.override_font_path is not a valid font file")
		return main_font
	var project_theme_path: String = ProjectSettings.get_setting("gui/theme/custom_font")
	if project_theme_path:
		main_font = load(project_theme_path)
		assert(main_font, "ProjectSettings/gui/theme/custom_font is not a valid font file")
		return main_font
	main_font = load(fallback_font_path)
	assert(main_font, "IVThemeInitializer.fallback_font_path is not a valid font file")
	return main_font


func _init() -> void:
	IVSettingsManager.changed.connect(_settings_listener)
	_main_theme = get_main_theme()
	_main_font = get_main_font()
	var multipliers := IVCoreSettings.gui_size_multipliers
	var n_gui_sizes := multipliers.size()
	_default_font_sizes.resize(n_gui_sizes)
	_medium_font_sizes.resize(n_gui_sizes)
	_large_font_sizes.resize(n_gui_sizes)
	for i in n_gui_sizes:
		_default_font_sizes[i] = roundi(multipliers[i] * default_font_base_size)
		_medium_font_sizes[i] = roundi(multipliers[i] * medium_font_base_size)
		_large_font_sizes[i] = roundi(multipliers[i] * large_font_base_size)
	if set_default_font:
		_main_theme.default_font = _main_font
	for mod in main_theme_mods:
		mod.call(_main_theme)
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	_set_gui_font_sizes(gui_size)



func add_gui_font_sizes(theme: Theme) -> void:
	theme.set_type_variation(&"MediumFont", &"Control")
	theme.set_type_variation(&"LargeFont", &"Control")
	theme.set_type_variation(&"MediumFixedFont", &"Control")
	theme.set_type_variation(&"LargeFixedFont", &"Control")
	theme.set_font_size(&"font_size", &"MediumFixedFont", medium_font_fixed_size)
	theme.set_font_size(&"font_size", &"LargeFixedFont", large_font_fixed_size)


#func add_borderless_color_picker_button(theme: Theme) -> void:
	#var empty_stylebox := StyleBoxTexture.new()
	#theme.set_stylebox(&"normal", &"BorderlessColorPickerButton", empty_stylebox)
	#theme.set_type_variation(&"BorderlessColorPickerButton", &"ColorPickerButton")


func get_label3d_names_font_size() -> int:
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	var names_percent: int = IVSettingsManager.get_setting(&"label3d_names_size_percent")
	var default_font_size := _default_font_sizes[gui_size]
	return roundi(default_font_size * names_percent / 100.0)


func get_label3d_symbols_font_size() -> int:
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	var symbols_percent: int = IVSettingsManager.get_setting(&"label3d_symbols_size_percent")
	var default_font_size := _default_font_sizes[gui_size]
	return roundi(default_font_size * symbols_percent / 100.0)


func _set_gui_font_sizes(gui_size: int) -> void:
	_main_theme.default_font_size = _default_font_sizes[gui_size]
	_main_theme.set_font_size(&"font_size", &"MediumFont", _medium_font_sizes[gui_size])
	_main_theme.set_font_size(&"font_size", &"LargeFont", _large_font_sizes[gui_size])
	_set_label3d_sizes()


func _set_label3d_sizes() -> void:
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	var names_percent: int = IVSettingsManager.get_setting(&"label3d_names_size_percent")
	var symbols_percent: int = IVSettingsManager.get_setting(&"label3d_symbols_size_percent")
	var default_font_size := _default_font_sizes[gui_size]
	var names_size := roundi(default_font_size * names_percent / 100.0)
	var symbols_size := roundi(default_font_size * symbols_percent / 100.0)
	label3d_font_size_changed.emit(names_size, symbols_size)


func _settings_listener(setting: StringName, value: Variant) -> void:
	match setting:
		&"gui_size":
			var gui_size: int = value
			_set_gui_font_sizes(gui_size)
		&"label3d_names_size_percent", &"label3d_symbols_size_percent":
			_set_label3d_sizes()
