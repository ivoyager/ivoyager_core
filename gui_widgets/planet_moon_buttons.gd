# planet_moon_buttons.gd
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
class_name IVPlanetMoonButtons
extends HBoxContainer

## GUI widget.
##
## This widget builds itself from an existing planetary system specified by
## [member star_name]. It arranges planets horizontally with moons vertically
## below.[br][br]
##
## An ancestor Control node must have property [param selection_manager] set
## to an [IVSelectionManager] before [signal IVGlobal.system_tree_ready].[br][br]
##
## To use in conjuction with [IVSunSliceButton], make both SIZE_FILL_EXPAND and give
## strech ratios: 1.0 (SunSliceButton) and 10.0 (this widget or container that
## contains this widget).[br][br]
##
## TODO: This class needs to provide a 'widget_resized' signal for parent useage.

const BODYFLAGS_PLANET_OR_DWARF_PLANET := IVBody.BodyFlags.BODYFLAGS_PLANET_OR_DWARF_PLANET
const BODYFLAGS_MOON := IVBody.BodyFlags.BODYFLAGS_MOON

const BODYFLAGS_SHOW_IN_NAVIGATION_PANEL := IVBody.BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL

const STAR_SLICE_MULTIPLIER := 0.05 # what fraction of star is in image "slice"?
const INIT_WIDTH := 560.0


# widget settings
@export var star_name := &"STAR_SUN"
@export var size_exponent := 0.4 # smaller values reduce differences in object sizes
@export var min_button_width_proportion := 0.05 # as proportion of total (roughly)
@export var min_body_size_ratio := 0.008929 # proportion of widget width, rounded
@export var column_separation_ratio := 0.007143 # proportion of widget width, rounded

# private
var _selection_manager: IVSelectionManager # get from ancestor selection_manager
var _currently_selected: Button
var _resize_multipliers: Dictionary[Control, Vector2] = {} # indexed by Control, holds Vector2
var _is_built := false

@onready var _mouse_only_gui_nav: bool = false # IVGlobal.settings.mouse_only_gui_nav



func _ready() -> void:
	IVGlobal.about_to_start_simulator.connect(_build)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	resized.connect(_resize)
	IVGlobal.setting_changed.connect(_settings_listener)
	_build()



func _build(_dummy := false) -> void:
	if _is_built:
		return
	if !IVGlobal.state.is_system_built:
		return
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	if !_selection_manager:
		return
	_is_built = true
	var column_separation := int(INIT_WIDTH * column_separation_ratio + 0.5)
	set(&"theme_override_constants/separation", column_separation)
	# calculate star "slice" relative size
	var star := IVBody.bodies[star_name]
	var min_body_size := roundf(INIT_WIDTH * min_body_size_ratio)
	# count & calcultate planet relative sizes
	var base_size := 0.0
	var total_width := 0.0
	var column_widths: Array[float] = [] # index 0, 1, 2,... will be planet/moon columns
	var planet_sizes: Array[float] = []
	var n_planets := 0
	var star_satellites := star.satellites
	for planet_name in star_satellites:
		var planet := star_satellites[planet_name]
		if not planet.flags & BODYFLAGS_PLANET_OR_DWARF_PLANET:
			continue
		base_size = planet.get_mean_radius() ** size_exponent
		planet_sizes.append(base_size)
		column_widths.append(base_size)
		total_width += base_size
		n_planets += 1
	var min_width := min_button_width_proportion * total_width
	for column in n_planets:
		if column_widths[column] < min_width:
			total_width += min_width - column_widths[column]
			column_widths[column] = min_width
	# scale everything to fit specified widget width
	var widget_scale: float = (INIT_WIDTH - (column_separation * n_planets)) / total_width
	var max_planet_size := 0.0
	for column in n_planets:
		column_widths[column] = roundf(column_widths[column] * widget_scale)
		planet_sizes[column] = roundf(planet_sizes[column] * widget_scale)
		if planet_sizes[column] < min_body_size:
			planet_sizes[column] = min_body_size
		if max_planet_size < planet_sizes[column]:
			max_planet_size = planet_sizes[column]
	# build the system button tree
	var column := 0
	for planet_name in star_satellites: # vertical box for each planet w/ its moons
		var planet := star_satellites[planet_name]
		if not planet.flags & BODYFLAGS_PLANET_OR_DWARF_PLANET or not planet.flags & BODYFLAGS_SHOW_IN_NAVIGATION_PANEL:
			continue
		# For each planet column, column_widths[column] sets the top Spacer
		# width (and therefore the column width) and planet_sizes[column] sets
		# the planet image size (which is sometimes smaller).
		var planet_vbox := VBoxContainer.new()
		planet_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		planet_vbox.size_flags_stretch_ratio = column_widths[column]
		add_child(planet_vbox)
		var spacer := Control.new()
		var spacer_height := roundf((max_planet_size - planet_sizes[column]) / 2.0)
		spacer.custom_minimum_size.y = spacer_height
		spacer.mouse_filter = MOUSE_FILTER_IGNORE
		_resize_multipliers[spacer] = Vector2(0.0, spacer_height / INIT_WIDTH)
		planet_vbox.add_child(spacer)
		_add_nav_button(planet_vbox, planet, planet_sizes[column])
		for moon_name in planet.satellites:
			var moon := planet.satellites[moon_name]
			if not moon.flags & BODYFLAGS_MOON or not moon.flags & BODYFLAGS_SHOW_IN_NAVIGATION_PANEL:
				continue
			base_size = roundf(pow(moon.get_mean_radius(), size_exponent) * widget_scale)
			if base_size < min_body_size:
				base_size = min_body_size
			_add_nav_button(planet_vbox, moon, base_size)
		column += 1


func _clear_procedural() -> void:
	_is_built = false
	_selection_manager = null
	_currently_selected = null
	_resize_multipliers.clear()
	for child in get_children():
		child.queue_free()


func _add_nav_button(box_container: BoxContainer, body: IVBody, image_size: float) -> void:
	var button := IVNavigationButton.new(body, image_size, _selection_manager)
	button.selected.connect(_on_nav_button_selected.bind(button))
	button.size_flags_horizontal = SIZE_FILL
	box_container.add_child(button)
	var size_multiplier := image_size / INIT_WIDTH
	_resize_multipliers[button] = Vector2(size_multiplier, size_multiplier)


func _resize() -> void:
	# Column widths are mostly controled by size_flags_stretch_ratio. However,
	# some planets are smaller than the minimum button width so we can't depend
	# on that for image sizing. We also need to resize the vertical spacer
	# above planets.
	# WARNING: Shrinking by user mouse drag works, but I think it is a little
	# iffy. We have a few images already smaller than their bounding buttons
	# (Ceres & Pluto, depending on min_button_width_proportion) and this is why
	# it is possible to shrink the widget before image resizing.
	var widget_width := size.x
	var column_separation := int(widget_width * column_separation_ratio + 0.5)
	set(&"theme_override_constants/separation", column_separation)
	for control: Control in _resize_multipliers:
		var multipliers: Vector2 = _resize_multipliers[control]
		control.custom_minimum_size = multipliers * widget_width


func _on_nav_button_selected(selected: Button) -> void:
	_currently_selected = selected
	if !_mouse_only_gui_nav and !get_viewport().gui_get_focus_owner():
		if selected.focus_mode != FOCUS_NONE:
			selected.grab_focus()


func _settings_listener(setting: StringName, _value: Variant) -> void:
	match setting:
		&"gui_size":
			if IVGlobal.state.is_system_built:
				_settings_resize()
#		&"mouse_only_gui_nav":
#			_mouse_only_gui_nav = value
#			if !_mouse_only_gui_nav and _currently_selected:
#				await get_tree().process_frame # wait for _mouse_only_gui_nav.gd
#				if _currently_selected.focus_mode != FOCUS_NONE:
#					_currently_selected.grab_focus()


func _settings_resize() -> void:
	# It's a hack, but but we hide our content so the widget can shrink with
	# its bounding container. The _resize() function then resizes images to fit
	# the widget.
	for child in get_children():
		(child as Control).hide()
	await get_tree().process_frame
	_resize()
	for child in get_children():
		(child as Control).show()
