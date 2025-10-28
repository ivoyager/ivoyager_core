# nav_buttons_system.gd
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
class_name IVNavButtonsSystem
extends HBoxContainer

## HBoxContainer widget that procedurally generates planet and moon [IVNavButton]
## instances that are sized and arranged as a navigable "solar system" (but not
## including the root star)
##
## This widget builds itself from an existing [IVBody] tree with root defined by
## [member star_name]. It arranges planets horizontally with moons vertically
## below each planet. Bodies are limited to the subset with BODYFLAGS_SHOW_IN_NAVIGATION_PANEL
## set in [member IVBody.flags] (this excludes the vast majority of small moons).[br][br]
##
## The widget fills available horizontal space, sizing body images and column
## widths accordingly. It will have a resulting minimum vertical size.
## TODO: Vertical size can be reduced using [member moon_number_scroll].[br][br]
##
## To use in conjuction with a Sun "slice" [IVNavButton], make both SIZE_FILL_EXPAND
## and give strech ratios: 1.0 (SunButton) and 10.0 (this widget or container that
## contains this widget).[br][br]



## [IVBody] name to build the planetary system from.
@export var star_name := &"STAR_SUN"
## Smaller values reduce differences in body sizes. 0.0 is no difference. 1.0 is
## "true scale". Note that a minimum visual size is set by [member min_body_size_proportion]. 
@export var scale_exponent := 0.35
## Minimum button width as a proportion of the widget width.
@export var min_button_width_proportion := 0.05
## Minimum body size as a proportion of the widget width.
@export var min_body_size_proportion := 0.01
## Column separation as a proportion of the widget width.
@export var column_separation_proportion := 0.01
## This many or more moons will be placed in a vertical ScrollContainer.
## This can be used to reduce the vertical size of the widget.
## @experimental: NOT YET IMPLEMENTED
@export var moon_number_scroll := 999


var _widget_width := 560.0 # init value; everything rescales on _resize()
var _resize_height_multipliers: Dictionary[Control, float] = {}
var _suppress_resize := true
var _is_built := false



func _ready() -> void:
	IVGlobal.system_tree_ready.connect(_build)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	resized.connect(_resize)
	_build()



func _build(_dummy := false) -> void:
	const BODYFLAGS_PLANET_OR_DWARF_PLANET := IVBody.BodyFlags.BODYFLAGS_PLANET_OR_DWARF_PLANET
	const BODYFLAGS_MOON := IVBody.BodyFlags.BODYFLAGS_MOON
	const BODYFLAGS_SHOW := IVBody.BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL
	
	if _is_built:
		return
	if !IVGlobal.state.is_system_built:
		return
	_is_built = true
	_suppress_resize = true
	var column_separation := int(_widget_width * column_separation_proportion + 0.5)
	set(&"theme_override_constants/separation", column_separation)
	
	# calculate star "slice" relative size
	var star := IVBody.bodies[star_name]
	var min_body_size := roundf(_widget_width * min_body_size_proportion)
	
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
		base_size = planet.get_mean_radius() ** scale_exponent
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
	var widget_scale: float = (_widget_width - (column_separation * n_planets)) / total_width
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
		if not planet.flags & BODYFLAGS_PLANET_OR_DWARF_PLANET or not planet.flags & BODYFLAGS_SHOW:
			continue
		
		# For each planet column, column_widths[column] sets the VBoxContainer
		# stretch ratio (and therefore the column width) and planet_sizes[column]
		# sets the planet image height (which can be smaller, e.g., for Ceres).
		var planet_vbox := VBoxContainer.new()
		planet_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		planet_vbox.size_flags_stretch_ratio = column_widths[column]
		add_child(planet_vbox)
		
		var planet_size := planet_sizes[column]
		var spacer := Control.new()
		var spacer_height := roundf((max_planet_size - planet_sizes[column]) / 2.0)
		spacer.mouse_filter = MOUSE_FILTER_IGNORE
		spacer.custom_minimum_size.y = spacer_height
		_resize_height_multipliers[spacer] = spacer_height / _widget_width
		
		planet_vbox.add_child(spacer)
		_add_nav_button(planet_vbox, planet_name, planet_size)
		for moon_name in planet.satellites:
			var moon := planet.satellites[moon_name]
			if not moon.flags & BODYFLAGS_MOON or not moon.flags & BODYFLAGS_SHOW:
				continue
			base_size = roundf(pow(moon.get_mean_radius(), scale_exponent) * widget_scale)
			if base_size < min_body_size:
				base_size = min_body_size
			_add_nav_button(planet_vbox, moon_name, base_size)
		column += 1
	
	_suppress_resize = false
	_resize()


func _clear_procedural() -> void:
	_is_built = false
	_resize_height_multipliers.clear()
	for child in get_children():
		child.queue_free()


func _add_nav_button(box_container: BoxContainer, body_name: StringName, image_size: float) -> void:
	var button := IVNavButton.create(body_name, Vector2(0.0, image_size))
	button.size_flags_horizontal = Control.SIZE_FILL
	button.size_flags_vertical = SIZE_SHRINK_BEGIN
	box_container.add_child(button)
	_resize_height_multipliers[button] = image_size / _widget_width


func _resize() -> void:
	if _suppress_resize:
		return
	var widget_width := size.x
	if _widget_width == widget_width:
		return
	_suppress_resize = true
	_widget_width = widget_width
	var column_separation := roundi(widget_width * column_separation_proportion)
	set(&"theme_override_constants/separation", column_separation)
	for control in _resize_height_multipliers:
		control.custom_minimum_size.y = _resize_height_multipliers[control] * widget_width
	_suppress_resize = false
