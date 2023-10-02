# global.gd
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

# This node is added as singleton 'IVGlobal'.
#
# Container arrays and dictionaries are never replaced, so it is safe to keep a
# local reference in class files.

# simulator state broadcasts
signal translations_imported() # IVTranslationImporter; useful for boot screen
signal data_tables_imported() # IVTableImporter
signal preinitializers_inited()
signal initializers_inited()
signal project_objects_instantiated() # IVProjectBuilder; IVGlobal.program populated
signal project_inited() # IVProjectBuilder; after all _ivcore_init() calls
signal project_nodes_added() # IVProjectBuilder; prog_nodes & gui_nodes added
signal project_builder_finished() # IVProjectBuilder; 1 frame after above
signal state_manager_inited()
signal world_environment_added() # on Main after I/O thread finishes (slow!)
signal about_to_build_system_tree()
signal system_tree_built_or_loaded(is_new_game) # still some I/O tasks to do!
signal system_tree_ready(is_new_game) # I/O thread has finished!
signal about_to_start_simulator(is_new_game) # delayed 1 frame after above
signal update_gui_requested() # send signals with GUI info now!
signal simulator_started()
signal pause_changed(is_paused)
signal user_pause_changed(is_paused) # ignores pause from sim stop
signal about_to_free_procedural_nodes() # on exit and game load
signal about_to_stop_before_quit()
signal about_to_quit()
signal about_to_exit()
signal simulator_exited()
signal game_save_started()
signal game_save_finished()
signal game_load_started()
signal game_load_finished()
signal run_state_changed(is_running) # is_system_built and !SceneTree.paused
signal network_state_changed(network_state) # IVEnums.NetworkState

# other broadcasts
signal setting_changed(setting, value)
signal camera_ready(camera)

# requests for state change
signal sim_stop_required(who, network_sync_type, bypass_checks) # see IVStateManager
signal sim_run_allowed(who) # all objects requiring stop must allow!
signal change_pause_requested(is_toggle, is_pause) # 2nd arg ignored if is_toggle
signal quit_requested(force_quit) # force_quit bypasses dialog
signal exit_requested(force_exit) # force_exit bypasses dialog
signal save_requested(path, is_quick_save) # ["", false] will trigger dialog
signal load_requested(path, is_quick_load) # ["", false] will trigger dialog
signal save_quit_requested()

# requests for camera action
signal move_camera_requested(selection, camera_flags, view_position, view_rotations,
		is_instant_move) # 1st arg can be null; all others optional

# requests for GUI
signal open_main_menu_requested()
signal close_main_menu_requested()
signal confirmation_requested(text, confirm_action, stop_sim, title_txt, ok_txt, cancel_txt)
signal options_requested()
signal hotkeys_requested()
signal credits_requested()
signal help_requested() # hooked up in Planetarium
signal save_dialog_requested()
signal load_dialog_requested()
signal close_all_admin_popups_requested() # main menu, options, etc.
signal rich_text_popup_requested(header_text, text)
signal open_wiki_requested(wiki_title)
signal show_hide_gui_requested(is_toggle, is_show) # 2nd arg ignored if is_toggle



# containers - write authority indicated; safe to localize container reference
var state := {} # IVStateManager & IVSaveManager; is_inited, is_running, etc.
var times: Array[float] = [] # IVTimekeeper [time (s, J2000), engine_time (s), solar_day (d)]
var date: Array[int] = [] # IVTimekeeper; Gregorian [year, month, day]
var clock: Array[int] = [] # IVTimekeeper; UT [hour, minute, second]
var program := {} # IVProjectBuilder instantiated objects (base or override classes)
var procedural_classes := {} # IVProjectBuilder defined script classes (base or override)
var assets := {} # AssetsInitializer loads from dynamic paths specified below
var settings := {} # IVSettingsManager
var themes := {} # IVThemeManager
var fonts := {} # IVFontManager
var bodies := {} # IVBody instances add/remove themselves; indexed by name
var world_targeting := [] # IVWorldControl & others; optimized data for 3D world selection
var top_bodies: Array[Node3D] = [] # IVBody instances add/remove themselves; just STAR_SUN for us
var selections := {} # IVSelectionManager(s)
var blocking_windows: Array[Window] = [] # add Windows that want & test for exclusivity

# read-only!
var ivoyager_version: String
var is_html5: bool = OS.has_feature('JavaScript')
var wiki: String # IVWikiInitializer sets; "wiki" (internal), "en.wiki", etc.
var debug_log: FileAccess # IVLogInitializer sets if debug build and debug_log_path



func _enter_tree() -> void:
	const plugin_utils := preload("../editor_plugin/plugin_utils.gd")
	var plugin_config := plugin_utils.get_config("res://addons/ivoyager_core/plugin.cfg")
	assert(plugin_config, "Could not load plugin.cfg")
	ivoyager_version = plugin_config.get_value("plugin", "version")

