# full_screen_button.gd
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
class_name IVFullScreenButton
extends Button

## Button widget that toggles full screen.
##
## Requires [IVFullScreenManager] (not added by default) and [member
## IVCoreSettings.allow_fullscreen_toggle] == true.

@export var full_screen_text := &"BUTTON_FULL_SCREEN"
@export var minimize_text := &"BUTTON_MINIMIZE"


var _full_screen_manager: IVFullScreenManager


func _ready() -> void:
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)
	
	
func _configure_after_core_inited() -> void:
	text = full_screen_text
	if not IVCoreSettings.allow_fullscreen_toggle:
		push_warning("Full screen toggle requires IVCoreSettings.allow_fullscreen_toggle == true")
		disabled = true
		return
	_full_screen_manager = IVGlobal.program.get(&"FullScreenManager")
	if not _full_screen_manager:
		push_warning("Full screen toggle requires IVFullScreenManager")
		disabled = true
		return
	process_mode = PROCESS_MODE_ALWAYS
	_full_screen_manager.fullscreen_changed.connect(_update_button)
	get_viewport().size_changed.connect(_update_button)
	IVGlobal.ui_dirty.connect(_update_button)
	_update_button()


func _pressed() -> void:
	_full_screen_manager.toggle_fullscreen()


func _update_button() -> void:
	var is_fullscreen := _full_screen_manager.is_fullscreen()
	text = minimize_text if is_fullscreen else full_screen_text
