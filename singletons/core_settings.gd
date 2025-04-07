# core_settings.gd
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
extends Node

## Added as singleton 'IVCoreSettings'.
##
## Modify properties or dictionary classes using res://ivoyager_override.cfg.
## Alternatively, you can modify values here using an initializer script. (See
## comments in core_initializer.gd.) [br][br]
##
## With very few exceptions, these should not be modified after program start!

var project_name := ""
var project_version := "" # external project can set for gamesave debuging
var is_modded := false # this is aspirational
var use_threads := true # false helps for debugging
var dynamic_lights := true
var nonphysical_energy_at_1_au := 1.5 # some blowout is good
var nonphysical_attenuation_exponent := 0.5 # physical is 2.0
var dynamic_orbits := true # allows use of orbit element rates
var sbg_mag_cutoff_override := INF # overrides small_bodies_group.tsv cutoff if <INF
var skip_splash_screen := true
var pause_only_stops_time := false # if true, Universe & TopGUI are set to process
var disable_pause := false
var disable_exit := false
var disable_quit := false

var use_internal_wiki := false # FIXME: WikiManager doesn't do anything yet

var start_time: float = 22.0 * IVUnits.YEAR # from J2000 epoch
var start_camera_fov: float = IVMath.get_focal_length_from_fov(35.0)
var allow_time_setting := false
var allow_time_reversal := false
var popops_can_stop_sim := true # false overrides stop_sim member in all popups
var limit_stops_in_multiplayer := true # overrides most stops
#var multiplayer_disables_pause := false # server can pause if false, no one if true
#var multiplayer_min_speed := 1
var allow_fullscreen_toggle := true
var auto_exposure_enabled := true
var vertecies_per_orbit: int = 500
var vertecies_per_orbit_low_res: int = 100 # for small bodies like asteroids
var max_camera_distance: float = 5e3 * IVUnits.AU
var obliquity_of_the_ecliptic: float = 23.439 * IVUnits.DEG
var ecliptic_rotation := IVMath.get_x_rotation_matrix(obliquity_of_the_ecliptic)

var body_labels_color := Color.WHITE
var body_labels_use_orbit_color := false # true overrides above

var cache_dir := "user://cache"

var enable_wiki := false # IVTableInitializer sends to the Tables plugin
var enable_precisions := false # IVTableInitializer sends to the Tables plugin

# Theses could be modified after init, but you would have to rebuild the 'Home' View.
var home_name := &"PLANET_EARTH"
var home_longitude := 0.0
var home_latitude := 0.0

## Set VisualInstance3D.layer based on object m_radius. See [member size_layers].
var apply_size_layers := true
## If apply_size_layers == true, all VisualInstance3D instances will have [param layers]
## set to one of n+1 values where this array contains n elements. Layer 0b0001
## is set if m_radius >= size_layers[0], 0b0010 if < size_layers[0], 0b0100 if
## < size_layers[1], etc.
var size_layers: Array[float] = [
	# larger m_radius gets mask 0b0001
	100.0 * IVUnits.KM, # smaller m_radius gets mask 0b0010
	0.1 * IVUnits.KM, # smaller m_radius gets mask 0b0100
]


## Use this dictionary to set GUI text color meanings globally.
var text_colors: Dictionary[StringName, Color] = {
	great = Color.CYAN,
	good = Color.GREEN,
	base = Color.WHITE,
	caution = Color.YELLOW,
	warning = Color.ORANGE,
	danger = Color(1, 0.2, 0, 1), # RED is hard to read
	flag = Color.FUCHSIA,
}


var wikipedia_locales: Array[String] = ["en"] # add locales present in data tables

var body_tables: Array[StringName] = [&"stars", &"planets", &"asteroids", &"moons", &"spacecrafts"]

var debug_log_path := "user://logs/debug.log" # modify or set "" to disable



func _enter_tree() -> void:
	IVFiles.init_from_config(self, IVGlobal.ivoyager_config, "core_settings")


## Return is the layers mask. Returns 1 if apply_size_layers == false.
func get_visualinstance3d_layers_for_size(m_radius: float) -> int:
	if !apply_size_layers:
		return 1
	var layers := 1
	for size in size_layers:
		if m_radius < size:
			layers <<= 1
	return layers
