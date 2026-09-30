# theme_manager.gd
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
## properties and (for dynamic) the global "gui_size" setting (a value of
## [member IVCoreSettings.gui_size_settings]). Every size here is in logical
## pixels, which the display scale maps to the screen (see [IVGraphicsManager]),
## so "gui_size" is relative to the screen's own scale.[br][br]
##
## With [member scale_icons_and_spacing], the icons, stylebox content margins and
## [member pixel_constants] the main theme uses, its own and Godot's default
## theme's, follow "gui_size" too, so a check box, a button's padding or a
## container's separation keeps its proportion to the text. Their authored sizes
## are the GUI_LARGE size, as the base font sizes are. An icon that is not a
## [DPITexture] keeps its size. Change these items through [member
## main_theme_mods]: one set on the main theme after init is replaced at the next
## "gui_size" change. A Control's own constant overrides follow "gui_size" under
## an [IVControlModSpacing].[br][br]


## Emitted when the body-name Label3D font size changes: the main theme's
## default_font_size modified by the "label3d_names_size_percent" setting.
signal label3d_font_size_changed(name_size: int)

## Emitted when the body symbol screen size changes: [member symbol_base_size] for
## the active GUI size modified by the "body_symbol_size_percent" setting.
signal body_symbol_size_changed(symbol_size: float)

## Emitted when the small-bodies symbol point size changes: [member symbol_base_size]
## for the active GUI size modified by the "small_bodies_symbol_size_percent" setting.
signal small_bodies_symbol_size_changed(symbol_size: float)


## If set, ignore ProjectSettings/gui/theme/custom and [member fallback_theme_path].
static var override_theme_path := ""
## Fallback theme if [member override_theme_path] and ProjectSettings/gui/theme/custom
## are not set.
static var fallback_theme_path := "res://addons/ivoyager_core/resources/ivoyager_theme.tres"
static var override_font_path := ""
static var fallback_font_path := "res://addons/ivoyager_assets/fonts/Roboto-NotoSansSymbols-merged.ttf"
## Names of the theme constants that are lengths in pixels, which follow "gui_size"
## (see class description). These are the constants Godot scales when it builds its
## default theme at a [code]gui/theme/default_theme_scale[/code], plus
## MarginContainer's margins and [code]outline_size[/code], which it builds at zero.
static var pixel_constants: Array[StringName] = [
	&"arrow_margin", &"button_margin", &"buttons_separation", &"check_h_separation",
	&"close_h_offset", &"close_v_offset", &"h_separation", &"h_width", &"icon_h_separation",
	&"icon_margin", &"icon_separation", &"indent", &"item_end_padding", &"item_margin",
	&"item_start_padding", &"label_width", &"line_separation", &"line_spacing", &"margin",
	&"margin_bottom", &"margin_left", &"margin_right", &"margin_top",
	&"minimum_grab_thickness", &"outline_size", &"port_hotzone_inner_extent",
	&"port_hotzone_outer_extent", &"resize_margin", &"scroll_border",
	&"scrollbar_h_separation", &"scrollbar_v_separation", &"search_bar_separation",
	&"separation", &"shadow_offset_x", &"shadow_offset_y", &"shadow_outline_size",
	&"side_margin", &"sv_height", &"sv_width", &"table_h_separation", &"table_v_separation",
	&"text_highlight_h_padding", &"text_highlight_v_padding", &"title_height",
	&"underline_spacing", &"v_separation",
]

## If true, the loaded font is assigned to the main theme's default font.
var set_default_font := true
## If true, the main theme's icons, stylebox content margins and [member
## pixel_constants] follow the "gui_size" setting like the dynamic fonts (see class
## description).
var scale_icons_and_spacing := true
## Callables applied (in order) to the main Theme during init. Append your own
## to add custom theme modifications.
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
## Fixed (gui_size-independent) font size for type variation "MediumFixedFont".
var medium_font_fixed_size := 20
## Fixed (gui_size-independent) font size for type variation "LargeFixedFont".
var large_font_fixed_size := 24
## Value multiplied by [member IVCoreSettings.gui_size_multipliers] for the
## 100%-reference symbol screen size (body and small-bodies symbols); the relevant
## percent setting is then applied. See [method get_body_symbol_size].
var symbol_base_size := 20


var _main_theme: Theme
var _main_font: Font
var _default_font_sizes: Array[int] = []
var _medium_font_sizes: Array[int] = []
var _large_font_sizes: Array[int] = []
var _default_symbol_sizes: Array[float] = []
var _gui_size_themes: Array[Theme] = [] # merged into the main theme at a "gui_size" change


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
	_default_symbol_sizes.resize(n_gui_sizes)
	for i in n_gui_sizes:
		_default_font_sizes[i] = roundi(multipliers[i] * default_font_base_size)
		_medium_font_sizes[i] = roundi(multipliers[i] * medium_font_base_size)
		_large_font_sizes[i] = roundi(multipliers[i] * large_font_base_size)
		_default_symbol_sizes[i] = multipliers[i] * symbol_base_size
	if set_default_font:
		_main_theme.default_font = _main_font
	for mod in main_theme_mods:
		mod.call(_main_theme)
	_build_gui_size_themes()
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	_apply_gui_size(gui_size)



## Default [member main_theme_mods] entry: registers the "MediumFont",
## "LargeFont", "MediumFixedFont", and "LargeFixedFont" type variations on
## [param theme].
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


## Returns the current Label3D font size for body name labels, derived from
## the active GUI size and the "label3d_names_size_percent" user setting.
func get_label3d_names_font_size() -> int:
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	var names_percent: int = IVSettingsManager.get_setting(&"label3d_names_size_percent")
	var default_font_size := _default_font_sizes[gui_size]
	return roundi(default_font_size * names_percent / 100.0)


## Returns the current body symbol screen size (logical px), derived from the active
## GUI size and the "body_symbol_size_percent" user setting.
func get_body_symbol_size() -> float:
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	var percent: int = IVSettingsManager.get_setting(&"body_symbol_size_percent")
	return _default_symbol_sizes[gui_size] * percent / 100.0


## Returns the current small-bodies symbol point size (logical px), derived from
## the active GUI size and the "small_bodies_symbol_size_percent" user setting.
func get_small_bodies_symbol_size() -> float:
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	var percent: int = IVSettingsManager.get_setting(&"small_bodies_symbol_size_percent")
	return _default_symbol_sizes[gui_size] * percent / 100.0


func _apply_gui_size(gui_size: int) -> void:
	_main_theme.merge_with(_gui_size_themes[gui_size])
	_set_label3d_sizes()


# Call once, before the first merge: it reads the main theme's items as authored.
func _build_gui_size_themes() -> void:
	# Each theme change is a synchronous pass over every Control, so everything that follows
	# the GUI size must arrive as one merge of a prebuilt theme.
	var source_themes: Array[Theme] = [ThemeDB.get_default_theme(), _main_theme] # main wins
	var multipliers := IVCoreSettings.gui_size_multipliers
	for i in multipliers.size():
		var gui_size_theme := Theme.new()
		gui_size_theme.default_font_size = _default_font_sizes[i]
		gui_size_theme.set_font_size(&"font_size", &"MediumFont", _medium_font_sizes[i])
		gui_size_theme.set_font_size(&"font_size", &"LargeFont", _large_font_sizes[i])
		if scale_icons_and_spacing:
			_add_scaled_items(gui_size_theme, source_themes, multipliers[i])
		_gui_size_themes.append(gui_size_theme)


func _add_scaled_items(gui_size_theme: Theme, source_themes: Array[Theme], multiplier: float
		) -> void:
	var scaled_icons: Dictionary[Texture2D, Texture2D] = {} # keeps a shared item shared
	var scaled_styleboxes: Dictionary[StyleBox, StyleBox] = {}
	for source_theme in source_themes:
		for theme_type in source_theme.get_icon_type_list():
			for icon_name in source_theme.get_icon_list(theme_type):
				var icon := source_theme.get_icon(icon_name, theme_type)
				if !scaled_icons.has(icon):
					scaled_icons[icon] = _get_scaled_icon(icon, multiplier)
				gui_size_theme.set_icon(icon_name, theme_type, scaled_icons[icon])
		for theme_type in source_theme.get_stylebox_type_list():
			for stylebox_name in source_theme.get_stylebox_list(theme_type):
				var stylebox := source_theme.get_stylebox(stylebox_name, theme_type)
				if !scaled_styleboxes.has(stylebox):
					scaled_styleboxes[stylebox] = _get_scaled_stylebox(stylebox, multiplier)
				gui_size_theme.set_stylebox(stylebox_name, theme_type, scaled_styleboxes[stylebox])
		for theme_type in source_theme.get_constant_type_list():
			for constant_name in source_theme.get_constant_list(theme_type):
				if pixel_constants.has(StringName(constant_name)):
					var constant := source_theme.get_constant(constant_name, theme_type)
					gui_size_theme.set_constant(constant_name, theme_type,
							roundi(constant * multiplier))


func _get_scaled_icon(icon: Texture2D, multiplier: float) -> Texture2D:
	var dpi_texture := icon as DPITexture
	if !dpi_texture:
		return icon
	var scaled_texture := dpi_texture.duplicate() as DPITexture
	scaled_texture.base_scale = dpi_texture.base_scale * multiplier
	return scaled_texture


func _get_scaled_stylebox(stylebox: StyleBox, multiplier: float) -> StyleBox:
	var scaled_stylebox := stylebox.duplicate() as StyleBox
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		# A negative content margin means "use the style's own", which has no size to scale.
		var margin := stylebox.get_content_margin(side)
		if margin > 0.0:
			# Rounded, as Godot rounds when it scales its default theme.
			scaled_stylebox.set_content_margin(side, roundf(margin * multiplier))
	return scaled_stylebox


func _set_label3d_sizes() -> void:
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	var names_percent: int = IVSettingsManager.get_setting(&"label3d_names_size_percent")
	var default_font_size := _default_font_sizes[gui_size]
	var names_size := roundi(default_font_size * names_percent / 100.0)
	label3d_font_size_changed.emit(names_size)


func _set_symbol_sizes() -> void:
	body_symbol_size_changed.emit(get_body_symbol_size())
	small_bodies_symbol_size_changed.emit(get_small_bodies_symbol_size())


func _settings_listener(setting: StringName, value: Variant) -> void:
	match setting:
		&"gui_size":
			var gui_size: int = value
			_apply_gui_size(gui_size)
			_set_symbol_sizes()
		&"label3d_names_size_percent":
			_set_label3d_sizes()
		&"body_symbol_size_percent":
			body_symbol_size_changed.emit(get_body_symbol_size())
		&"small_bodies_symbol_size_percent":
			small_bodies_symbol_size_changed.emit(get_small_bodies_symbol_size())
