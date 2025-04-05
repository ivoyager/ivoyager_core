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
var attenuation_exponent := 0.5 # 2.0 is natural but << needed for non-physical
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


var default_cached_settings: Dictionary[StringName, Variant] = {
	# save/load (only matters if Save pluin is enabled)
	&"save_base_name" : "I Voyager",
	&"append_date_to_save" : true,
	&"pause_on_load" : false,
	&"autosave_time_min" : 10,

	# camera
	&"camera_transfer_time" : 1.0,
	&"camera_mouse_in_out_rate" : 1.0,
	&"camera_mouse_move_rate" : 1.0,
	&"camera_mouse_pitch_yaw_rate" : 1.0,
	&"camera_mouse_roll_rate" : 1.0,
	&"camera_key_in_out_rate" : 1.0,
	&"camera_key_move_rate" : 1.0,
	&"camera_key_pitch_yaw_rate" : 1.0,
	&"camera_key_roll_rate" : 1.0,

	# UI & HUD display
	&"gui_size" : IVGlobal.GUISize.GUI_MEDIUM,
	&"viewport_names_size" : 15,
	&"viewport_symbols_size" : 25,
	&"point_size" : 3,
	&"hide_hud_when_close" : true, # restart or load required

	# graphics/performance
	&"starmap" : IVGlobal.StarmapSize.STARMAP_16K,

	# misc
	&"mouse_action_releases_gui_focus" : true,

	# cached but not in IVOptionsPopup
	# FIXME: Obsolete below?
	&"save_dir" : "",
	&"pbd_splash_caption_open" : false,
	&"mouse_only_gui_nav" : false,

}


var default_input_map: Dictionary[StringName, Variant] = {
	# Each "event_dict" must have event_class; all other keys are properties
	# to be set on the InputEvent. Don't remove an action -- just give it an
	# empty array to disable.
	#
	# Note: I'M TOTALLY IGNORANT ABOUT JOYPAD CONTROLLERS! SOMEONE PLEASE
	# HELP!
	#
	# Note 2: ui_xxx actions have hard-coding problems; see issue #43663.
	# We can't set them here and (even in godot.project) we can't use key
	# modifiers. Hopefully in 4.0 these can be fully customized.
	
#	ui_up = [
#		{&"event_class" : &"InputEventKey", scancode = KEY_UP, &"alt_pressed" : true},
#		{&"event_class" : &"InputEventJoypadButton", button_index = 12},
#	],
#	ui_down = [
#		{&"event_class" : &"InputEventKey", scancode = KEY_DOWN, &"alt_pressed" : true},
#		{&"event_class" : &"InputEventJoypadButton", button_index = 13},
#	],
#	ui_left = [
#		{&"event_class" : &"InputEventKey", scancode = KEY_LEFT, &"alt_pressed" : true},
#		{&"event_class" : &"InputEventJoypadButton", button_index = 14},
#	],
#	ui_right = [
#		{&"event_class" : &"InputEventKey", scancode = KEY_RIGHT, &"alt_pressed" : true},
#		{&"event_class" : &"InputEventJoypadButton", button_index = 15},
#	],
	
	&"camera_up" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_UP},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_UP, &"ctrl_pressed" : true},
	],
	&"camera_down" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_DOWN},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_DOWN, &"ctrl_pressed" : true},
	],
	&"camera_left" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_LEFT},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_LEFT, &"ctrl_pressed" : true},
	],
	&"camera_right" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_RIGHT},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_RIGHT, &"ctrl_pressed" : true},
	],
	&"camera_in" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_PAGEDOWN}
	],
	&"camera_out" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_PAGEUP}
	],
	
	&"recenter" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_KP_5},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_D},
	],
	&"pitch_up" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_KP_8},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_E},
	],
	&"pitch_down" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_KP_2},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_C},
	],
	&"yaw_left" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_KP_4},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_S},
	],
	&"yaw_right" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_KP_6},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_F},
	],
	&"roll_left" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_KP_1},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_X},
	],
	&"roll_right" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_KP_3},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_V},
	],
	
	&"select_up" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_UP, &"shift_pressed" : true}
	],
	&"select_down" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_DOWN, &"shift_pressed" : true}
	],
	&"select_left" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_LEFT, &"shift_pressed" : true}
	],
	&"select_right" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_RIGHT, &"shift_pressed" : true}
	],
	&"select_forward" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_PERIOD}
	],
	&"select_back" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_COMMA}
	],
	&"next_system" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_Y}
	],
	&"previous_system" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_Y, &"shift_pressed" : true}
	],
	&"next_star" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_T}
	],
	&"previous_star" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_T, &"shift_pressed" : true}
	],
	&"next_planet" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_P}
	],
	&"previous_planet" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_P, &"shift_pressed" : true}
	],
	&"next_nav_moon" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_M}
	],
	&"previous_nav_moon" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_M, &"shift_pressed" : true}
	],
	&"next_moon" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_N}
	],
	&"previous_moon" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_N, &"shift_pressed" : true}
	],
	&"next_asteroid" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_H}
	],
	&"previous_asteroid" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_H, &"shift_pressed" : true}
	],
	&"next_asteroid_group" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_G}
	],
	&"previous_asteroid_group" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_G, &"shift_pressed" : true}
	],
	&"next_comet" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_J}
	],
	&"previous_comet" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_J, &"shift_pressed" : true}
	],
	&"next_spacecraft" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_K}
	],
	&"previous_spacecraft" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_K, &"shift_pressed" : true}
	],
	&"toggle_orbits" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_O}
	],
	&"toggle_symbols" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_I}
	],
	&"toggle_names" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_L}
	],
	&"toggle_all_gui" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_G, &"ctrl_pressed" : true}
	],
	&"toggle_fullscreen" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_F, &"ctrl_pressed" : true}
	],
	&"toggle_pause" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_SPACE}
	],
	&"incr_speed" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_EQUAL},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_BRACERIGHT},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_BRACKETRIGHT}, # grrrr. Browsers!
	],
	&"decr_speed" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_MINUS},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_BRACELEFT},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_BRACKETLEFT},
	],
	&"reverse_time" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_BACKSPACE},
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_BACKSLASH},
	],
		
	&"toggle_options" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_O, &"ctrl_pressed" : true}
	],
	&"toggle_hotkeys" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_H, &"ctrl_pressed" : true}
	],
	&"load_file" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_L, &"ctrl_pressed" : true}
	],
	&"quickload" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_L, &"alt_pressed" : true}
	],
	&"save_as" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_S, &"ctrl_pressed" : true}
	],
	&"quicksave" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_S, &"alt_pressed" : true}
	],
	&"quit" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_Q, &"ctrl_pressed" : true}
	],
	&"save_quit" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_Q, &"alt_pressed" : true}
	],
	
	# Used by ProjectCyclablePanels GUI mod (which is used by Planetarium)
	&"cycle_next_panel" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_QUOTELEFT}
	],
	&"cycle_prev_panel" : [
		{&"event_class" : &"InputEventKey", &"keycode" : KEY_QUOTELEFT, &"shift_pressed" : true}
	],
	
}

# *****************************************************************************
# Settings that IVTableInitializer sends to the Table Importer plugin

 
var enable_wiki := false
var enable_precisions := false
var tables: Dictionary[StringName, String] = {
	asset_adjustments = "res://addons/ivoyager_core/data/solar_system/asset_adjustments.tsv",
	asteroids = "res://addons/ivoyager_core/data/solar_system/asteroids.tsv",
	body_classes = "res://addons/ivoyager_core/data/solar_system/body_classes.tsv",
	dynamic_lights = "res://addons/ivoyager_core/data/solar_system/dynamic_lights.tsv",
	omni_lights = "res://addons/ivoyager_core/data/solar_system/omni_lights.tsv",
	models = "res://addons/ivoyager_core/data/solar_system/models.tsv",
	moons = "res://addons/ivoyager_core/data/solar_system/moons.tsv",
	planets = "res://addons/ivoyager_core/data/solar_system/planets.tsv",
	rings = "res://addons/ivoyager_core/data/solar_system/rings.tsv",
	small_bodies_groups = "res://addons/ivoyager_core/data/solar_system/small_bodies_groups.tsv",
	spacecrafts = "res://addons/ivoyager_core/data/solar_system/spacecrafts.tsv",
	stars = "res://addons/ivoyager_core/data/solar_system/stars.tsv",
	views = "res://addons/ivoyager_core/data/solar_system/views.tsv",
	visual_groups = "res://addons/ivoyager_core/data/solar_system/visual_groups.tsv",
	wiki_extras = "res://addons/ivoyager_core/data/solar_system/wiki_extras.tsv",
}
var table_project_enums := [
	IVSmallBodiesGroup.SBGClass,
	IVGlobal.Confidence,
	IVBody.BodyFlags,
	IVCamera.CameraFlags,
	IVView.ViewFlags,
	IVGlobal.ShadowMask,
]
var merge_table_constants := {}
var replacement_missing_values := {} # not recomended to use this


# *****************************************************************************

var wikipedia_locales: Array[String] = ["en"] # add locales present in data tables

var body_tables: Array[StringName] = [&"stars", &"planets", &"asteroids", &"moons", &"spacecrafts"]


# TODO: Move to IVTranslationImporter
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
	IVFiles.init_from_config(self, IVGlobal.ivoyager_config, "core_settings")


## Return is the layers mask. Returns 0b0001 if apply_size_layers == false.
func get_visualinstance3d_layers_for_size(m_radius: float) -> int:
	if !apply_size_layers:
		return 0b0001
	var layers := 0b0001
	for size in size_layers:
		if m_radius < size:
			layers <<= 1
	return layers
