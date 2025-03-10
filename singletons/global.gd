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

## Added as singleton 'IVGlobal'.
##
## Array and dictionary references are never overwritten, so it is safe to keep
## local references in class files.

# simulator state broadcasts
signal about_to_run_initializers() # IVCoreInitializer; after plugin preinitializers
signal translations_imported() # IVTranslationImporter; useful for boot screen
signal data_tables_imported() # IVTableImporter
signal preinitializers_inited()
signal initializers_inited()
signal project_objects_instantiated() # IVCoreInitializer; IVGlobal.program populated
signal project_inited() # IVCoreInitializer; after above
signal project_nodes_added() # IVCoreInitializer; prog_nodes & gui_nodes added
signal project_builder_finished() # IVCoreInitializer; 1 frame after above
signal state_manager_inited()
signal world_environment_added() # on Main after I/O thread finishes (slow!)
signal about_to_build_system_tree() # new or loading game
signal add_system_tree_item_started(item: Node) # new or loading game (Body or SmallBodiesGroup)
signal add_system_tree_item_finished(item: Node) # after all I/O work has completed for item
signal system_tree_built_or_loaded(is_new_game: bool) # still ongoing I/O tasks!
signal system_tree_ready(is_new_game: bool) # I/O thread has finished
signal about_to_start_simulator(is_new_game: bool) # delayed 1 frame after above
signal update_gui_requested() # send signals with GUI info now!
signal simulator_started()
signal pause_changed(is_paused: bool)
signal user_pause_changed(is_paused: bool) # ignores pause from sim stop
signal about_to_free_procedural_nodes() # on exit and game load
signal about_to_stop_before_quit()
signal about_to_quit()
signal about_to_exit()
signal simulator_exited()
signal run_state_changed(is_running: bool) # is_system_built and !SceneTree.paused
signal network_state_changed(network_state: bool) # IVEnums.NetworkState

# other broadcasts
signal setting_changed(setting: StringName, value: Variant)
signal camera_ready(camera: Camera3D)

# requests for state change
signal start_requested()
signal sim_stop_required(who: Object, network_sync_type: int, bypass_checks: bool) # IVStateManager
signal sim_run_allowed(who: Object) # all objects requiring stop must allow!
signal change_pause_requested(is_toggle: bool, is_pause: bool) # 2nd arg ignored if is_toggle
signal quit_requested(force_quit: bool) # force_quit bypasses dialog
signal exit_requested(force_exit: bool) # force_exit bypasses dialog
signal save_requested(path: String, is_quick_save: bool) # ["", false] will trigger dialog
signal load_requested(path: String, is_quick_load: bool) # ["", false] will trigger dialog
signal resume_requested() # user probably wants to close the main menu
signal save_quit_requested()

# requests for camera action
signal move_camera_requested(selection: Object, camera_flags: int, view_position: Vector3,
		view_rotations: Vector3, is_instant_move: bool) # 1st arg can be null; all others optional

# requests for GUI
signal open_main_menu_requested()
signal close_main_menu_requested()
signal confirmation_requested(text: StringName, confirm_action: Callable, stop_sim: bool,
		title_txt: StringName, ok_txt: StringName, cancel_txt: StringName)
signal options_requested()
signal hotkeys_requested()
signal credits_requested()
signal help_requested() # hooked up in Planetarium
signal close_all_admin_popups_requested() # main menu, options, etc.
signal open_wiki_requested(wiki_title: String)
signal show_hide_gui_requested(is_toggle: bool, is_show: bool) # 2nd arg ignored if is_toggle


# containers - write authority indicated; safe to localize container reference

## Maintained by [IVStateManager]. Mostly boolean keys: is_inited, is_running, etc.
var state: Dictionary[StringName, Variant] = {}
## Maintained by [IVTimekeeper]. Holds [time (s, J2000), engine_time (s), solar_day (d)]
## by default or possibly additional elements.
var times: Array[float] = []
## Maintained by [IVTimekeeper]. Holds Gregorian [year, month, day].
var date: Array[int] = []
## Maintained by [IVTimekeeper]. Holds UT [hour, minute, second].
var clock: Array[int] = []
## Populated by [IVCoreInitializer]. Holds instantiated program objects (base or override classes).
var program: Dictionary[StringName, Object] = {}
## Populated by [IVCoreInitializer]. Holds script classes for procedural objects (base or override).
var procedural_classes: Dictionary[StringName, Resource] = {}
## Populated by [AssetsInitializer]. Loaded assets from dynamic paths specified in [IVCoreSettings].
var assets: Dictionary[StringName, Resource] = {}
## Maintained by [IVSettingsManager].
var settings: Dictionary[StringName, Variant] = {}
## Maintained by [IVThemeManager].
var themes: Dictionary[StringName, Theme] = {}
## Maintained by [IVFontManager].
var fonts: Dictionary[StringName, FontFile] = {}
## Maintained by [IVBody] instances that add/remove themselves. Indexed by [param name].
## TODO: Make this a static class dictionary.
var bodies: Dictionary[StringName, Object] = {}
## Maintained by [IVSmallBodiesGroup] instances that add/remove themselves. Indexed by [param name].
## TODO: Make this a static class dictionary.
var small_bodies_groups: Dictionary[StringName, Object] = {}
## Maintained by [IVWorldControl] & others. Otimized data for 3D world selection
var world_targeting := []
## Maintained by [IVBody] instances that add/remove themselves. Only has one body
## for a single star system (i.e., STAR_SUN in base solar system).
var top_bodies: Array[Node3D] = []
## Maintained by [IVSelectionManager] instances.
## TODO: Make this a static class dictionary.
var selections: Dictionary[StringName, Object] = {}
## Maintained by Windows instances that want & test for exclusivity.
var blocking_windows: Array[Window] = []
## For project use. Not used by I, Voyager.
var project := {}

# read-only!
var ivoyager_version: String
var assets_version: String
var wiki: String # IVWikiInitializer sets; "wiki" (internal), "en.wiki", etc.
var debug_log: FileAccess # IVLogInitializer sets if debug build and debug_log_path
var ivoyager_config: ConfigFile = IVPluginUtils.get_config_with_override(
		"res://addons/ivoyager_core/ivoyager_core.cfg",
		"res://ivoyager_override.cfg", "res://ivoyager_override2.cfg")



func _enter_tree() -> void:
	var plugin_config := IVPluginUtils.get_config("res://addons/ivoyager_core/plugin.cfg")
	assert(plugin_config, "Could not load plugin.cfg")
	ivoyager_version = plugin_config.get_value("plugin", "version")
	var assets_config := IVPluginUtils.get_config("res://addons/ivoyager_assets/assets.cfg")
	if assets_config and assets_config.has_section("ivoyager_assets"):
		assets_version = assets_config.get_value("ivoyager_assets", "version")
