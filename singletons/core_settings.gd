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

## Singleton [IVCoreSettings] holds Core plugin settings.
##
## All settings here should be set before or during the first step of
## [IVCoreInitializer] init by config file, preinitializer script, project
## autoload, or something similar. See [IVCoreInitializer] class documentation
## for details on how to do this.[br][br]
##
## [b]Important Class File Docs[/b][br][br]
##
## 1. [IVUniverseTemplate] for scene tree construction.[br]
## 2. Singletons [IVCoreInitializer], [IVCoreSettings], [IVGlobal], and
##    [IVStateManager] for program init and state management.[br]
## 3. [IVBody] for the physical 3D world. Also has roadmap details.[br]
## 4. [IVOrbit] for orbital mechanics. Has more roadmap related to spacecraft
##    thrust implementation.


# Dev note: Don't add non-Godot class dependencies in this file! These are
# avoided here to prevent circular reference issues.


## Set false to disable thread use throughout the Core plugin. This
## can be helpful for debugging. Some class files also have property
## [param use_threads]. In these classes, both this setting and the file
## setting must be true for threads to be used.
var use_threads := true

## If true, [IVTimekeeper] will set [member Engine.time_scale] to follow changes
## in game speed. Note that ivoyager_core almost never uses [code]delta[/code]
## from [code]_process()[/code], and compensates for [member Engine.time_scale]
## in the rare cases where it does. So this has no effect on the simulator.
var manage_engine_time_scale := true

## See [IVDynamicLight].
var dynamic_lights := true
## See [IVDynamicLight]. Values just over 1.0 give a small but realistic
## looking blowout Earth.
var nonphysical_energy_at_1_au := 1.2
## See [IVDynamicLight]. Real-world physical is 2.0 (1/r^2). A much smaller
## value is needed unless there is camera compensation.
var nonphysical_attenuation_exponent := 0.5
## If <INF, overrides magnitude cutoff specified in small_bodies_group.tsv.
var sbg_mag_cutoff_override := INF
## By default, the simulator starts without waiting (as in the Planetarium).
## If using a splash screen, set this value to true and start the simulation
## using [method IVStateManager.start] (e.g., via [IVStartButton] in the
## splash screen menu).
var wait_for_start := false
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

## Start time as an array of [year, month, day, hour, minute, second]. Used by
## [IVTimekeeper].
var start_time_date_clock: Array[int] = [2025, 1, 1, 0, 0, 0]
## If true, start time is Terrestrial Time (TT), otherwise, Universal Time (UT).
## Used by [IVTimekeeper]. See also [member IVTimekeeper.terrestrial_time_clock].
var start_time_is_terrestrial_time := false

## Used by [IVCamera].
var start_camera_fov: float = IVMath.get_fov_from_focal_length(24.0)

## Enables time setting functionality in [IVTimekeeper] and GUI widgets. Also
## needed for OS time synchronization. (Used by Planetarium.)
var allow_time_setting := false
## Enables time reversal in [IVSpeedManager] and elsewhere. (Used by Planetarium.)
var allow_time_reversal := false
## If true (default), "admin" popups like the main menu, options, etc., will
## stop the simulator while open. If false, the simulator will continue running.
var popops_can_stop_sim := true
## If true (default), overrides most "stop simulator" mechanics for multiplayer
## games. See [IVStateManager] for comments on WIP multiplayer code.
var limit_stops_in_multiplayer := true # overrides most stops

#var multiplayer_disables_pause := false # server can pause if false, no one if true
#var multiplayer_min_speed := 1

## Set true to enable fullscreen toggling. See also [IVFullScreenManager], which
## is not present in default Core initialization.
var allow_fullscreen_toggle := false
## Sets resolution of orbit/trajectory lines used by [IVOrbitVisual]. See
## [IVResourceInitializer] for construction of common orbit/trajectory meshes. 
var vertecies_per_orbit: int = 500
## Sets resolution of orbit/trajectory lines used by [IVSBGOrbitsVisual] (e.g.,
## for 10000s of asteroids). See [IVResourceInitializer] for construction of
## common orbit/trajectory meshes. 
var vertecies_per_orbit_low_res: int = 100
## Defines the maximum visual extent of open conics (i.e., parabolic and hyperbolic
## trajectories) relative to the unit conic. See [IVResourceInitializer].
var open_conic_max_radius := 1000.0
## Limits camera distance. Used by [IVCamera].
var max_camera_distance: float = 5e3 * IVUnits.AU
## Font color used for [IVBodyLabel] instances. See also [member
## body_labels_use_orbit_color].
var body_labels_color := Color.WHITE
## If true, [IVBodyLabel] font colors will maintain the same values as the
## corresponding orbit lines, which vary and are user settable. Overrides
## [member body_labels_color].
var body_labels_use_orbit_color := false
## Directory used (created if needed) for cache files. See [IVCacheHandler].
var cache_dir := "user://cache"
## Enables float precisions in [IVTableData]. This is used by Planetarium to
## reproduce data table significant digits in GUI display. (Probably not needed
## for most game usage.)
var enable_precisions := false
## Sets initial GUI selection and [IVCamera] location in a new game.
var home_name := &"PLANET_EARTH"


var home_longitude := 0.0 ## REMOVE: Not used

## Set all [member VisualInstance3D.layer] values based on size scale.
## See [member size_layers].
var apply_size_layers := true
## Defines size "scales" used to set [member VisualInstance3D.layer] values.
## These layers are needed for shadows to work over vast scale differences,
## from the rings of Saturn to small spacecraft. Shadows are cast by different
## [IVDynamicLight] instances in each size scale defined in this array. If the
## array has 2 values, that defines 3 "size scales" (>= index 0, >= index 1,
## < index 1). These 3 scales will set bit 0b0001, 0b0010, and 0b0100
## (respectively) in the layer value.[br][br]
## 
## [member VisualInstance3D.layer] will be set for the visual model used by
## a body based on its [member IVBody.mean_radius].[br][br]
##
## See [method get_visualinstance3d_layer_for_size].[br][br]
## 
## To disable this mechanism, set [member apply_size_layers] = false. Layers
## won't be modified and [IVDynamicLight] won't be used ([OmniLight3D] will be
## used instead).[br][br]
## 
## Note: [IVDynamicLight] lighting is broken when using Compatibility
## renderer (e.g., in an HTML5 export). The system will be deactivated
## automatically in this situation.
var size_layers: Array[float] = [
	# larger mean_radius gets mask 0b0001
	100.0 * IVUnits.KM, # smaller mean_radius gets mask 0b0010
	0.1 * IVUnits.KM, # smaller mean_radius gets mask 0b0100
]
## Contains all data tables that specify IVBody instances. Used by
## [IVAssetPreloader], [IVTableSystemBuilder], and possibly elsewhere.
var body_tables: Array[StringName] = [&"stars", &"planets", &"asteroids", &"moons", &"spacecrafts"]


## @depricated: This is not used by the plugin and will be removed.
var text_colors: Dictionary[StringName, Color] = {
	great = Color.CYAN,
	good = Color.GREEN,
	base = Color.WHITE,
	caution = Color.YELLOW,
	warning = Color.ORANGE,
	danger = Color.RED,
	flag = Color.FUCHSIA,
}



func _enter_tree() -> void:
	IVFiles.init_from_config(self, IVGlobal.ivoyager_config, "core_settings")
	assert(gui_size_multipliers.size() == IVGlobal.GUISize.size())



## Return is the appropriate layer mask for [param mean_radius] specified
## by [member size_layers]. Returns 1 if [member apply_size_layers] == false
## (which is the default [member VisualInstance3D.layer] value).
func get_visualinstance3d_layer_for_size(mean_radius: float) -> int:
	if not apply_size_layers:
		return 1
	var layer := 1
	for size in size_layers:
		if mean_radius < size:
			layer <<= 1
	return layer
