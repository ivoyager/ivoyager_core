# core_settings.gd
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
## * [IVUniverseTemplate] for scene tree construction.[br]
## * [IVCoreInitializer] & [IVCoreSettings] for plugin init & settings.[br]
## * [IVGlobal] & [IVStateManager] for runtime state management.[br]
## * [IVBody] for the physical 3D world. (Also has roadmap details.)[br]
## * [IVOrbit] for orbital mechanics. (Has more roadmap for spacecraft thrust).


# Dev note: Don't add non-Godot class dependencies in this file! These are
# avoided here to prevent circular reference issues.


## Set false to disable thread use throughout the Core plugin. This
## can be helpful for debugging. Some class files also have property
## [param use_threads]. In these classes, both this setting and the file
## setting must be true for threads to be used.
var use_threads := true

## If true (default), [IVTimekeeper] will set [member Engine.time_scale] to
## follow changes in game speed. Note that ivoyager_core almost never uses
## [code]delta[/code] from [code]_process()[/code] and compensates for
## [member Engine.time_scale] in the rare cases where it does. So this setting
## has no effect on simulator function either way.
var manage_engine_time_scale := true

## See [IVDynamicLight].
var dynamic_lights := true
## See [IVDynamicLight]. Values just over 1.0 give a small but realistic
## looking blowout Earth.
var nonphysical_energy_at_1_au := 1.6
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
## Sizes available for setting "gui_size". See also [member gui_size_multipliers].
var gui_size_settings: Dictionary[StringName, int] = {
	GUI_SMALL = 0,
	GUI_MEDIUM = 1,
	GUI_LARGE = 2,
	GUI_EXTRA_LARGE = 3,
}
## Size multipliers for each of [member gui_size_settings]. Before adjusting,
## consider effects on font sizing in [IVThemeManager] (font sizes are rounded
## to the nearest integer after multiplication). See also [IVControlModResizable].
var gui_size_multipliers: Array[float] = [0.75, 1.0, 1.25, 1.5]

## Start time as an array of [year, month, day, hour, minute, second]. Used by
## [IVTimekeeper].
var start_time_date_clock: Array[int] = [2026, 1, 1, 0, 0, 0]
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
## Sets resolution of the common sphere mesh used by all spheroid bodies. See
## [IVResourceInitializer] for mesh construction. See also [member sphere_rings].
var sphere_radial_segments := 128
## Sets resolution of the common sphere mesh used by all spheroid bodies. See
## [IVResourceInitializer] for mesh construction. See also [member
## sphere_radial_segments].
var sphere_rings := 64
## Sets closed-orbit state-path resolution ([method IVOrbit.refresh_state_path]): knots per family
## (uniform anomaly + uniform tangent-turn, so up to ~2x total at high eccentricity). [IVPathVisual]'s
## rebased line Hermite-refines between these knots for smoothness, and its render-frame pin holds the
## line ON the body at any density — so the worst mid-knot Hermite bow (scales as N^-4; meters-scale
## for a Juno-class e = 0.98 orbit at 500) shows only mid-field, where there is no reference to see it
## against. Density's real cost is the per-knot scan on every rebake.
var vertecies_per_orbit: int = 500
## Sets state-path knots per [IVTrajectory] segment (uniform anomaly). A transfer segment spans years
## to decades, so its mid-knot Hermite bow is larger than a closed orbit's (~340 m worst on Voyager
## Sun legs at 500, N^-4) — but the render-frame pin holds the line ON the body at any density, and
## the bow shows only mid-field, unreferenced. This is also the Tier-1 coarse polyline density; the
## whole-trajectory knot total sets the per-rebake scan cost, which dominates rebased-mode CPU.
var vertecies_per_trajectory_segment: int = 500
## Sets resolution of the shared unit conic meshes drawing all non-rebased orbit lines in
## [IVPathVisual]. Facet angle peaks at the apsides at ~(2 pi / N) / sqrt(1 - e^2), so N must cover
## the highest-eccentricity orbit displayed (4096 keeps e = 0.98 under ~0.5 deg). The meshes are
## shared, so the cost is per drawn vertex, not per body.
var vertecies_per_conic_mesh: int = 4096
## Sets resolution of orbit/trajectory lines used by [IVSBGOrbitsVisual] (e.g.,
## for 10000s of asteroid orbits as [MultiMeshInstance3D]). See
## [IVResourceInitializer] for construction of common orbit/trajectory meshes. 
var vertecies_per_orbit_low_res: int = 100
## Defines the maximum visual extent of open conics (i.e., parabolic and hyperbolic
## trajectories) relative to the unit conic. See [IVResourceInitializer].
var open_conic_max_radius := 1000.0
## Limits camera distance. Used by [IVCamera].
var max_camera_distance: float = 5e3 * IVUnits.AU
## Radius multiplier used to set [member GeometryInstance3D.visibility_range_end]
## in [IVBodyVisual] and [IVRings].
var radius_multiplier_visibility_range_end := 4000.0
## Enables "farwarp" compression: beyond a camera-relative start distance (see
## [member farwarp_start_ratio]), body model spaces, HUD position symbols, and
## line/point shaders are re-rendered along the camera ray at logarithmically
## compressed distance with angular size exactly preserved, so distant objects
## (e.g., the Moon and Sun viewed from a spacecraft) are not culled by the
## camera far plane. True [IVBody] positions are never modified. See
## [IVFarwarpManager].
var apply_farwarp := true
## Farwarp compression starts at camera-to-target distance times this ratio;
## everything closer is untouched (the remap is exactly identity inside the
## start distance). Must stay well under 1e6 (the [IVCamera] far-plane
## multiplier); 1e4 leaves 100x headroom while the compressed universe spans
## less than ~29x the start distance. See [member apply_farwarp].
var farwarp_start_ratio := 1e4
## A body's model space is farwarp-remapped only while its true angular radius
## ([member IVBody.mean_radius] / camera distance, in radians) exceeds this
## cutoff; smaller bodies keep true model positions (their models are
## distance-culled and their always-offset HUD symbols represent them). Keep at
## or below [code]1.0 / radius_multiplier_visibility_range_end[/code] so every
## model that would pass its visibility range is pulled inside the far plane.
## Bodies exempt from distance culling (stars) bypass the cutoff. See
## [member apply_farwarp].
var farwarp_angular_cutoff := 0.00025
## Directory used (created if needed) for cache files. See [IVCacheHandler].
var cache_dir := "user://cache"
## Enables float precisions in [IVTableData]. This is used by Planetarium to
## reproduce data table significant digits in GUI display. (Probably not needed
## for most game usage.)
var enable_precisions := false
## Sets initial GUI selection and [IVCamera] location in a new game.
var home_name := &"PLANET_EARTH"


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

## Path to the position-symbol atlas: a grid of white-on-transparent shapes (see
## [code]resources/ivoyager_symbol_atlas_generator.py[/code] for the shipped default).
## Loaded at runtime by [IVAssetPreloader]. Replace with a project atlas by overriding
## this path together with [member symbol_atlas_columns] and [member symbol_atlas_rows].
var symbol_atlas_path := "res://addons/ivoyager_core/resources/ivoyager_symbol_atlas.png"
## Columns in [member symbol_atlas_path]. A body or [IVSmallBodiesGroup] symbol type
## is a row-major index into the atlas ([code]col = symbol_type % symbol_atlas_columns[/code],
## [code]row = symbol_type / symbol_atlas_columns[/code]); a symbol type of -1 means
## "no shape" (a flat point). The grid must cover the largest symbol type used in data tables.
var symbol_atlas_columns := 3
## Rows in [member symbol_atlas_path]. See [member symbol_atlas_columns].
var symbol_atlas_rows := 4


## If >0.0, an artificial stroboscopic visual effect is generated for fast
## rotating bodies that is more stable and pleasing than the "natural"
## stroboscopic effect from process frames. Value is a simulated frames per
## second for [IVBody] rotation. Values much smaller than actual frame rates
## (e.g., ~10.0 or ~5.0) might give desirable visual effects. Default 0.0
## disables the effect.
var stroboscope_frames_per_second := 0.0
## Minimum blur (in radians) when a body exhibits stroboscopic rotation. [member
## stroboscope_frames_per_second] must be greater than 0.0.
var stroboscope_minimum_blur := 0.025
## Motion blur multiplier when a body exhibits stroboscopic rotation. [member
## stroboscope_frames_per_second] must be greater than 0.0.
var stroboscope_motion_blur := 0.1


## @deprecated: This is not used by the plugin and will be removed.
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


## Called by [IVStateManager] to test valid settings.
func assert_valid_settings() -> void:
	assert(gui_size_multipliers.size() == gui_size_settings.size())
	assert(stroboscope_frames_per_second >= 0.0)
	assert(farwarp_start_ratio > 0.0)
	assert(farwarp_angular_cutoff > 0.0)
	assert(symbol_atlas_columns > 0 and symbol_atlas_rows > 0)


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
