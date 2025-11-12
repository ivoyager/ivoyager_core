# global.gd
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

## Added as singleton "IVGlobal".
##
## Dev note: Don't add ANY non-Godot class dependencies! These could cause
## circular reference issues.

# Array and dictionary references are never overwritten, so it is safe (and
# faster) to keep local references to these containers to in class files.

# Developer note: Don't add any non-Godot dependencies in this file! That
# messes up static class dependencies on this global.




## Emitted by [IVTranslationImporter] after translations imported. This is early
## in [IVCoreInitializer] init before program objects have been added. May be
## useful for boot or splash screen.  
signal translations_imported()
## Emitted by [IVTableInitializer] after data tables have been postprocessed.
## This is early in [IVCoreInitializer] init before program objects have been
## added.
signal data_tables_postprocessed()

## Signal from [IVStateManager] to [IVTableSystemBuilder] to build the system tree.
## DON'T USE THIS. Use [signal IVStateManager.about_to_build_system_tree] instead.
signal build_system_tree_now()

## FIXME: Fix redundant updates to pattern described. 
## Emitted by IVStateManager immediately before simulator start. All objects
## that signal "something_changed" for UI should signal now. UI that polls
## instead of responding (if any) should update too.
signal ui_dirty() 

# other broadcasts

signal current_camera_changed(camera: Camera3D)
signal camera_tree_changed(camera: Camera3D, parent: Node3D, star_orbiter: Node3D, star: Node3D)
signal camera_fov_changed(fov: float)
signal viewport_size_changed(size: Vector2)



# requests for UI
signal confirmation_required(text: StringName, action: Callable, stop_sim: bool,
		title_txt: StringName, ok_txt: StringName, cancel_txt: StringName)
signal main_menu_requested()
signal close_main_menu_requested()
signal options_requested()
signal hotkeys_requested()
signal close_admin_popups_required() # main menu, options, etc.
signal show_hide_gui_requested(is_toggle: bool, is_show: bool) # 2nd arg ignored if is_toggle


## Sizes available for setting "gui_size". See also [member IVCoreSettings.gui_size_multipliers].
enum GUISize {
	GUI_SMALL,
	GUI_MEDIUM,
	GUI_LARGE,
}

enum StarmapSize {
	STARMAP_8K,
	STARMAP_16K,
}

enum Confidence {
	CONFIDENCE_NO,
	CONFIDENCE_DOUBTFUL,
	CONFIDENCE_UNKNOWN,
	CONFIDENCE_PROBABLY,
	CONFIDENCE_YES,
}


## Shadow masking for semi-transparent shadows (from Saturn Rings).
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

## Duplicated from ivoyager_save plugin. Safe to use if plugin is not present.
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



## Maintained by [IVTimekeeper]. Holds [time (s, J2000), engine_time (s), solar_day (d)]
## by default or possibly additional elements.
var times: Array[float] = []
## Maintained by [IVTimekeeper]. Holds Gregorian [year, month, day].
var date: Array[int] = []
## Maintained by [IVTimekeeper]. Holds UT [hour, minute, second].
var clock: Array[int] = []
## Populated by [IVCoreInitializer]. Holds instantiated program objects (base or override classes).
var program: Dictionary[StringName, Object] = {}
## Populated by [IVResourceInitializer].
var resources: Dictionary[StringName, Resource] = {}
## For project use. Not used by I, Voyager.
var project := {}

## Project can set if needed. Persisted by IVSaveManager.
var game_mod := ""
## Read-only!
var ivoyager_version: String
## Read-only!
var assets_version: String

## Read-only! The plugin ConfigFile generated from res://addons/ivoyager_core/ivoyager_core.cfg
## with possible overrides in res://ivoyager_override.cfg and res://ivoyager_override2.cfg.
var ivoyager_config: ConfigFile = IVPluginUtils.get_config_with_override(
		"res://addons/ivoyager_core/ivoyager_core.cfg",
		"res://ivoyager_override.cfg",
		"res://ivoyager_override2.cfg")
## Read-only! Indicates project running with Compatibility renderer.
var is_gl_compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"



func _enter_tree() -> void:
	var plugin_config := IVPluginUtils.get_config("res://addons/ivoyager_core/plugin.cfg")
	assert(plugin_config, "Could not load plugin.cfg")
	ivoyager_version = plugin_config.get_value("plugin", "version")
	var assets_config := IVPluginUtils.get_config("res://addons/ivoyager_assets/assets.cfg")
	if assets_config and assets_config.has_section("ivoyager_assets"):
		assets_version = assets_config.get_value("ivoyager_assets", "version")


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	ui_dirty.connect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	viewport_size_changed.emit(get_viewport().get_visible_rect().size)
