# core_settings.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2023 Charlie Whitfield
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

# This node is added as singleton 'IVCoreSettings'.
#
# Modify properties or dictionary classes using res://ivoyager_override.cfg.
# Alternatively, you can modify values here using an initializer script. (See
# comments in core_initializer.gd.)
#
# With very few exceptions, these should not be modified after program start!

var project_name := ""
var project_version := "" # external project can set for gamesave debuging
var is_modded := false # this is aspirational
var enable_save_load := true
var save_file_extension := "IVoyagerSave"
var save_file_extension_name := "I Voyager Save"
var use_threads := true # false helps for debugging
var dynamic_orbits := true # allows use of orbit element rates
var sbg_mag_cutoff_override := INF # overrides small_bodies_group.tsv cutoff if <INF
var skip_splash_screen := true
var pause_only_stops_time := false # if true, Universe & TopGUI are set to process
var disable_pause := false
var disable_exit := false
var disable_quit := false

var enable_wiki := false
var enable_precisions := false
var use_internal_wiki := false # FIXME: WikiManager doesn't do anything yet

var start_time: float = 22.0 * IVUnits.YEAR # from J2000 epoch
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
var cache_dir := "user://cache"

# Theses could be modified after init, but you would have to rebuild the 'Home' View.
var home_name := "PLANET_EARTH"
var home_longitude := 0.0
var home_latitude := 0.0


var colors := { # user settable colors in program_refs/settings_manager.gd
	normal = Color.WHITE,
	good = Color.GREEN,
	warning = Color.YELLOW,
	danger = Color(1.0, 0.5, 0.5), # "red" is hard to read
}

var shared_resources := {
	# Values can be resource paths or preloaded resources. IVSharedInitializer
	# loads any paths at project init.
	
	# shaders
	&"points_id_shader" : "res://addons/ivoyager_core/shaders/points.id.gdshader",
	&"points_l4l5_id_shader" : "res://addons/ivoyager_core/shaders/points.l4l5.id.gdshader",
	&"orbit_id_shader" : "res://addons/ivoyager_core/shaders/orbit.id.gdshader",
	&"orbits_id_shader" : "res://addons/ivoyager_core/shaders/orbits.id.gdshader",
	&"rings_shader" : "res://addons/ivoyager_core/shaders/rings.gdshader",
	
	# additional items are constructed & added by initializers/shared_initializer.gd
}

var postprocess_tables: Array[String] = [
	"res://addons/ivoyager_core/data/solar_system/asset_adjustments.tsv",
	"res://addons/ivoyager_core/data/solar_system/asteroids.tsv",
	"res://addons/ivoyager_core/data/solar_system/body_classes.tsv",
	"res://addons/ivoyager_core/data/solar_system/omni_lights.tsv",
	"res://addons/ivoyager_core/data/solar_system/models.tsv",
	"res://addons/ivoyager_core/data/solar_system/moons.tsv",
	"res://addons/ivoyager_core/data/solar_system/planets.tsv",
	"res://addons/ivoyager_core/data/solar_system/small_bodies_groups.tsv",
	"res://addons/ivoyager_core/data/solar_system/spacecrafts.tsv",
	"res://addons/ivoyager_core/data/solar_system/stars.tsv",
	"res://addons/ivoyager_core/data/solar_system/visual_groups.tsv",
	"res://addons/ivoyager_core/data/solar_system/wiki_extras.tsv"
]

var table_project_enums := [
	IVEnums.SBGClass,
	IVEnums.Confidence,
	IVEnums.BodyFlags,
]

var wikipedia_locales: Array[String] = ["en"] # add locales present in data tables

var body_tables: Array[String] = ["stars", "planets", "asteroids", "moons", "spacecrafts"] # ordered!

# We search for assets based on "file_prefix" and sometimes other name elements
# like "albedo". To build a model, IVModelManager first looks for an existing
# model in models_search (1st path element to last). Failing that, it will use
# the generic IVSpheroidModel and search for map textures in maps_search. If it
# can't find "<file_prifix>.albedo" in maps_search, it will use fallback_albedo_map.

var asset_replacement_dir := ""  # replaces all "ivoyager_assets" below

var models_search: Array[String] = ["res://addons/ivoyager_assets/models"] # prepend to prioritize
var maps_search: Array[String] = ["res://addons/ivoyager_assets/maps"]
var bodies_2d_search: Array[String] = ["res://addons/ivoyager_assets/bodies_2d"]
var rings_search: Array[String] = ["res://addons/ivoyager_assets/rings"]

var asset_paths := {
	starmap_8k = "res://addons/ivoyager_assets/starmaps/starmap_8k.jpg",
	starmap_16k = "res://addons/ivoyager_assets/starmaps/starmap_16k.jpg",
}
var asset_paths_for_load := { # loaded into "assets" dict by IVAssetInitializer
	primary_font = "res://addons/ivoyager_assets/fonts/Roboto-NotoSansSymbols-merged.ttf",
	fallback_albedo_map = "res://addons/ivoyager_assets/fallbacks/blank_grid.jpg",
	fallback_body_2d = "res://addons/ivoyager_assets/fallbacks/blank_grid_2d_globe.256.png",
#	fallback_model = "res://addons/ivoyager_assets/models/phobos/Phobos.1_1000.glb", # implement in 0.0.14
}
var translations: Array[String] = [
	# Added here so extensions can modify. Note that IVTranslationImporter will
	# process text (eg, interpret \uXXXX) and report duplicate keys only if
	# import file has compress=false. For duplicates, 1st in array below will
	# be kept. So prepend this array if you want to override ivoyager text keys.
	"res://addons/ivoyager_core/data/text/entities_text.en.translation",
	"res://addons/ivoyager_core/data/text/gui_text.en.translation",
	"res://addons/ivoyager_core/data/text/hints_text.en.translation",
	"res://addons/ivoyager_core/data/text/long_text.en.translation",
]

var debug_log_path := "user://logs/debug.log" # modify or set "" to disable



func _enter_tree() -> void:
	var config: ConfigFile = IVFiles.get_config_with_override("res://addons/ivoyager_core/core.cfg",
			"res://ivoyager_override.cfg", "res://ivoyager_override2.cfg")
	IVFiles.init_from_config(self, config, "core_settings")

