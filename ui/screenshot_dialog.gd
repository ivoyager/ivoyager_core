# screenshot_dialog.gd
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
class_name IVScreenshotDialog
extends FileDialog

## File dialog that chooses where to write a captured screenshot.
##
## Opens on [signal IVScreenshotManager.dialog_requested] and hands the chosen path back via
## [method IVScreenshotManager.save_pending]. The image is already captured by the time this
## opens, so taking time here does not change what gets written.[br][br]
##
## Add to your scene tree under IVTopUI; see [IVUniverseTemplate].

## Stop the sim while the dialog is open, as the other popups do.
@export var stop_sim := true

var _screenshot_manager: IVScreenshotManager


func _ready() -> void:
	hide()
	# IVScreenshotManager is a "program" node that does not exist yet when this scene loads,
	# so the connection has to wait for core init (as IVOptionsPopup does). Connecting in
	# _ready() would silently no-op forever.
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	_screenshot_manager = IVGlobal.program.get(&"ScreenshotManager")
	if !_screenshot_manager:
		return # a project may have removed it from IVCoreInitializer.program_nodes
	add_filter("*.png", "PNG Image")
	_screenshot_manager.dialog_requested.connect(_open)
	file_selected.connect(_on_file_selected)
	visibility_changed.connect(_on_visibility_changed)


func _open(suggested_path: String) -> void:
	if visible:
		return
	popup_centered()
	current_path = suggested_path
	deselect_all()


func _on_file_selected(path: String) -> void:
	_screenshot_manager.save_pending(path)


func _on_visibility_changed() -> void:
	if !stop_sim:
		return
	if visible:
		IVStateManager.require_stop(self)
	else:
		IVStateManager.allow_run(self)
