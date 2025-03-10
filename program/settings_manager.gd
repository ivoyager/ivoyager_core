# settings_manager.gd
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
class_name IVSettingsManager
extends IVCacheManager

## Defines and manages user settings.
##
## Non-default settings are persisted in a cache file.[br][br]
##
## Many (but not necessarily all) user settings are settable in [IVOptionsPopup].


const BodyFlags: Dictionary = IVEnums.BodyFlags


func _init() -> void:
	super()
	# project vars - modify on signal 'IVGlobal.project_objects_instantiated'
	cache_file_name = "settings.ivbinary"
	cache_file_version = 1
	defaults = {
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
		&"gui_size" : IVEnums.GUISize.GUI_MEDIUM,
		&"viewport_names_size" : 15,
		&"viewport_symbols_size" : 25,
		&"point_size" : 3,
		&"hide_hud_when_close" : true, # restart or load required
	
		# graphics/performance
		&"starmap" : IVEnums.StarmapSize.STARMAP_16K,
	
		# misc
		&"mouse_action_releases_gui_focus" : true,
	
		# cached but not in IVOptionsPopup
		&"save_dir" : "",
		&"pbd_splash_caption_open" : false,
		&"mouse_only_gui_nav" : false,
	
		}
	
	# read-only
	current = IVGlobal.settings


func _on_change_current(setting: StringName) -> void:
	IVGlobal.setting_changed.emit(setting, current[setting])
