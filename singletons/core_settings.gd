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

## Added as singleton "IVCoreSettings".
##
## Modify properties or dictionary classes using res://ivoyager_override.cfg.
## Alternatively, you can modify values here using an initializer script. (See
## comments in core_initializer.gd.) [br][br]
##
## With very few exceptions, these should not be modified after program start!



## Set false to disable thread use throughout the ivoyager_core plugin. This
## can be helpful for debugging. Some class files also have property
## [param use_threads]. In these classes, both this setting and the file
## setting must be true for threads to be used.
var use_threads := true

## Specifies [Environment] properties from data table environment.tsv that are
## applied by [IVWorldEnvironment]. I, Voyager's WorldEnvironment can be
## disabled in [IVCoreInitializer].
var environment := &"ENVIRONMENT_PLANETARIUM"
## Specifies [CameraAttributes] properties from data table camera_attributes.tsv
## that are applied by [IVWorldEnvironment]. If this row has auto_exposure_enabled
## and project uses Compatibility renderer, a fallback will be used.
## I, Voyager's WorldEnvironment can be disabled in [IVCoreInitializer].
var camera_attributes := &"CAMERA_ATTRIBUTES_HARD_REALISM"

## @experimental: Possible future implementation. (Sim implements practiccal
## lighting only for now.)
var use_physical_light := false
## @experimental: Possible future implementation. (Sim implements practiccal
## lighting only for now.)
var camera_attributes_physical := &"CAMERA_ATTRIBUTES_PHYSICAL_HARD_REALISM"

## See [IVDynamicLight].
var dynamic_lights := true
## See [IVDynamicLight].
var nonphysical_energy_at_1_au := 1.2 # some blowout is good
## See [IVDynamicLight].
var nonphysical_attenuation_exponent := 0.5 # physical is 2.0
## If <INF, overrides magnitude cutoff specified in small_bodies_group.tsv.
var sbg_mag_cutoff_override := INF
## By default, the simulator starts without waiting (as in the Planetarium).
## If using a splash screen, set this value to true and start the simulation
## using [method IVStateManager.start()] (e.g., via [IVStartButton] in the
## splash screen menu).
var wait_for_start_request := false
## if true, Universe is set to process_mode = PROCESS_MODE_ALWAYS. See [IVStateManager].
## @depricate: figure it out from Universe?
var pause_only_stops_time := false
## See [IVStateManager].
var disable_pause := false
## See [IVStateManager].
var disable_exit := false
## See [IVStateManager].
var disable_quit := false
## Size multipliers corresponding to [enum IVGlobal.GUISize]. Before adjusting,
## consider effects on font sizing in [IVThemeManager] (font sizes are rounded
## to the nearest integer after multiplication). See also [IVControlModResizable].
var gui_size_multipliers: Array[float] = [0.75, 1.0, 1.25]

## From J2000 epoch.
var start_time: float = 22.0 * IVUnits.YEAR
var start_camera_fov: float = IVMath.get_fov_from_focal_length(24.0)
var allow_time_setting := false

var allow_time_reversal := false
var popops_can_stop_sim := true # false overrides stop_sim member in all popups
var limit_stops_in_multiplayer := true # overrides most stops
#var multiplayer_disables_pause := false # server can pause if false, no one if true
#var multiplayer_min_speed := 1
var allow_fullscreen_toggle := true
var auto_exposure_enabled := true
var vertecies_per_orbit: int = 500
var vertecies_per_orbit_low_res: int = 100 # for 10000s of small bodies like asteroids
var open_conic_max_radius := 1000.0 # for unit conic (p = 1.0)
var max_camera_distance: float = 5e3 * IVUnits.AU
var body_labels_color := Color.WHITE
## If true, overrides [member body_labels_color].
var body_labels_use_orbit_color := false
## See [IVCacheHandler].
var cache_dir := "user://cache"
## [IVTableInitializer] sends this value to the 
## [url=https://github.com/ivoyager/ivoyager_tables]Tables plugin[/url].
var enable_precisions := false

var home_name := &"PLANET_EARTH"
var home_longitude := 0.0
var home_latitude := 0.0

## Set VisualInstance3D.layer based on object mean_radius. See [member size_layers].
var apply_size_layers := true
## If apply_size_layers == true, all VisualInstance3D instances will have [param layers]
## set to one of n+1 values where this array contains n elements. Layer 0b0001
## is set if mean_radius >= size_layers[0], 0b0010 if < size_layers[0], 0b0100 if
## < size_layers[1], etc.
var size_layers: Array[float] = [
	# larger mean_radius gets mask 0b0001
	100.0 * IVUnits.KM, # smaller mean_radius gets mask 0b0010
	0.1 * IVUnits.KM, # smaller mean_radius gets mask 0b0100
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


## Holds all data tables that specify IVBody instances. Used by [IVAssetPreloader]
## and [IVTableSystemBuilder] (and possibly elsewhere).
var body_tables: Array[StringName] = [&"stars", &"planets", &"asteroids", &"moons", &"spacecrafts"]



func _enter_tree() -> void:
	IVFiles.init_from_config(self, IVGlobal.ivoyager_config, "core_settings")
	assert(gui_size_multipliers.size() == IVGlobal.GUISize.size())



## Return is the appropriate layers mask for [param mean_radius] specified
## by [member size_layers]. Returns 1 if [member apply_size_layers] == false.
func get_visualinstance3d_layers_for_size(mean_radius: float) -> int:
	if !apply_size_layers:
		return 1
	var layers := 1
	for size in size_layers:
		if mean_radius < size:
			layers <<= 1
	return layers
