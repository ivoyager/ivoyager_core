# global.gd
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

## Singleton [IVGlobal] provides global properties, signals, and enums.
##
## Dictionaries and arrays are usually populated and/or updated by a single
## external class. Container references are never overwritten, so it's safe
## to keep local references in class files; this is particularly useful for
## optimized access to simulator "time" at [member times][0].[br][br]
##
## Almost all signals are emitted by external code.[br][br]
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


## Emitted by [IVTranslationImporter] after translations imported. This is early
## in [IVCoreInitializer] init before program objects have been added. May be
## useful for boot or splash screen.  
signal translations_imported()
## Emitted by [IVTableInitializer] after data tables have been postprocessed.
## This is early in [IVCoreInitializer] init before program objects have been
## added.
signal data_tables_postprocessed()
## Emitted by [IVStateManager] immediately before simulator start. All objects
## that signal "something_changed" for UI should signal now. UI that polls
## (instead of responding to signals) should update too.
signal ui_dirty() 
## This signal should be emitted by whatever Camera3D class becomes current.
## (There is no Viewport signal so it is up to the newly active camera to signal.)
signal current_camera_changed(camera: Camera3D)
## This signal should be emitted by any Camera3D class used in the simulator.
## It tells the simulator where the camera is for graphic and other updating purposes.
signal camera_tree_changed(camera: Camera3D, parent: Node3D, star_orbiter: Node3D, star: Node3D)
## This signal should be emitted by any Camera3D class used in the simulator.
## It's used for things like size compensation in [IVBodyLabel].
signal camera_fov_changed(fov: float)
## This signal is emitted by [IVGlobal] code connected to the root viewport.
## Signals when the viewport size changes and also on [signal ui_dirty].
signal viewport_size_changed(size: Vector2)
## Emit from anywhere for [IVConfirmationDialog].
signal confirmation_required(text: StringName, action: Callable, stop_sim: bool,
		title_txt: StringName, ok_txt: StringName, cancel_txt: StringName)
## Emit from anywhere for [IVMainMenuBasePopup].
signal main_menu_requested()
## Emit from anywhere to close [IVMainMenuBasePopup].
signal close_main_menu_requested()
## Emit from anywhere for [IVOptionsPopup].
signal options_requested()
## Emit from anywhere for [IVHotkeysPopup].
signal hotkeys_requested()
## Emit from anywhere to require closing of all "admin" popups (main menu, options, etc.).
signal close_admin_popups_required()
## Emit from anywere to request show/hide all GUI. This is listened to by
## [IVShowHideUI]. The second arg is ignored if [param is_toggle] is true.
signal show_hide_gui_requested(is_toggle: bool, is_show: bool)


## Sizes available for setting "gui_size". See also [member IVCoreSettings.gui_size_multipliers].
enum GUISize {
	GUI_SMALL,
	GUI_MEDIUM,
	GUI_LARGE,
}

## Resolution choice for the background starmap; see [IVAssetPreloader].
enum StarmapSize {
	STARMAP_8K,
	STARMAP_16K,
}

## Generic confidence levels for table-driven values. Used by data tables
## where a fact may be doubtful, unknown, or probable.
enum Confidence {
	CONFIDENCE_NO,
	CONFIDENCE_DOUBTFUL,
	CONFIDENCE_UNKNOWN,
	CONFIDENCE_PROBABLY,
	CONFIDENCE_YES,
}

## Shadow masking for semi-transparent shadows used by [IVDynamicLight] and
## [IVRings] (for Saturn's rings).
enum ShadowMask {
	SHADOW_MASK_01 = 0b0001_0000_0000, # almost no shadow
	SHADOW_MASK_02 = 0b0010_0000_0000,
	SHADOW_MASK_03 = 0b0011_0000_0000,
	SHADOW_MASK_04 = 0b0100_0000_0000,
	SHADOW_MASK_05 = 0b0101_0000_0000,
	SHADOW_MASK_06 = 0b0110_0000_0000,
	SHADOW_MASK_07 = 0b0111_0000_0000,
	SHADOW_MASK_08 = 0b1000_0000_0000,
	SHADOW_MASK_09 = 0b1001_0000_0000,
	SHADOW_MASK_10 = 0b1010_0000_0000,
	SHADOW_MASK_11 = 0b1011_0000_0000,
	SHADOW_MASK_12 = 0b1100_0000_0000,
	SHADOW_MASK_13 = 0b1101_0000_0000,
	SHADOW_MASK_14 = 0b1110_0000_0000,
	SHADOW_MASK_FULL = 0b1111_0000_0000, # full shadow
}

## Duplicated from I, Voyager's Save plugin ([enum IVSaveUtils.PersistMode]).
## This is used in the Core plugin because the Save plugin may not be present.
enum PersistMode {
	NO_PERSIST, ## Non-persist object.
	PERSIST_PROPERTIES_ONLY, ## Object will not be freed (Node only; must have stable NodePath).
	PERSIST_PROCEDURAL, ## Object will be freed and rebuilt on game load (Node or RefCounted).
}


## Persist mode for the ivoyager_save plugin. Safe to use if plugin is not present.
const NO_PERSIST := PersistMode.NO_PERSIST
## Persist mode for the ivoyager_save plugin. Safe to use if plugin is not present.
const PERSIST_PROPERTIES_ONLY := PersistMode.PERSIST_PROPERTIES_ONLY
## Persist mode for the ivoyager_save plugin. Safe to use if plugin is not present.
const PERSIST_PROCEDURAL := PersistMode.PERSIST_PROCEDURAL



## Maintained by [IVTimekeeper] and [IVSpeedManager]. Holds [0] time,
## [1] speed_multiplier, [2] clock_time, [3] julian_day_number (as a whole
## number float).[br][br]
##
## Simulator [param time] at index 0 is Terrestrial Time with J2000 epoch in
## units defined by [constant IVUnits.SECOND].[br][br]
##
## [param speed_multiplier] is the same as [member Engine.time_scale] with
## default [member IVCoreSettings.manage_engine_time_scale] == true and
## [member IVCoreSettings.allow_time_reversal] == false, but can differ
## otherwise. See [IVSpeedManager] for details.[br][br]
##
## See [IVTimekeeper] for [param clock_time] and [param julian_day_number].
## Note that indexes may be added in the future for implementation of epoch
## changes (see TODO comment in [IVAstronomy]).
var times: Array[float] = [0.0, 1.0, 0.0, 0.0]
## Maintained by [IVTimekeeper]. Represents the fractional part of [member
## IVTimekeeper.clock_time] as clock integers: [0] hour, [1] minute, [2] second.
var clock: Array[int] = [0, 0, 0]
## Maintained by [IVTimekeeper]. Holds Gregorian calendar integers: [0] year,
## [1] month, [2] day.
var date: Array[int] = [0, 0, 0]
## Maintained by [IVTimekeeper]. Holds [0] Q, [1] YQ, [2] YM, where Q is quarter
## (1 - 4) and YQ and YM are cumulative counts of quarter and month since year
## 0. The latter two are monotonic increasing values.
var date_aux: Array[int] = [0, 0, 0]

## Populated by [IVCoreInitializer]. Holds instantiated "init" and "program"
## objects (base or override classes).
var program: Dictionary[StringName, Object] = {}
## Populated by [IVResourceInitializer]. Holds shaders and constructed resources
## that can be shared, e.g., a common sphere mesh (for all spheroid models) and
## a common circle mesh (for all closed orbit visuals). 
var resources: Dictionary[StringName, Resource] = {}


## Project can set if needed. Persisted by [IVSaveManager] if the Save plugin is present.
var game_mod := ""
## The Core plugin version from res://addons/ivoyager_core/plugin.cfg. Read only!
var ivoyager_version: String
## Assets version from res://addons/ivoyager_assets/assets.cfg (if present). Read only!
var assets_version: String
## The Core plugin ConfigFile generated from res://addons/ivoyager_core/ivoyager_core.cfg
## with possible overrides in res://ivoyager_override.cfg and res://ivoyager_override2.cfg.
## Read only!
var ivoyager_config: ConfigFile = IVPluginUtils.get_config_with_override(
		"res://addons/ivoyager_core/ivoyager_core.cfg",
		"res://ivoyager_override.cfg",
		"res://ivoyager_override2.cfg")
## Indicates project running with Compatibility renderer. Read only!
var is_gl_compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"



func _enter_tree() -> void:
	var plugin_config := IVPluginUtils.get_config("res://addons/ivoyager_core/plugin.cfg")
	assert(plugin_config, "Could not load plugin.cfg")
	ivoyager_version = plugin_config.get_value("plugin", "version")
	var assets_config := IVPluginUtils.get_config("res://addons/ivoyager_assets/assets.cfg")
	if assets_config and assets_config.has_section("ivoyager_assets"):
		assets_version = assets_config.get_value("ivoyager_assets", "version")


func _ready() -> void:
	get_tree().get_root().size_changed.connect(_on_viewport_size_changed)
	ui_dirty.connect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	viewport_size_changed.emit(get_tree().get_root().get_visible_rect().size)
