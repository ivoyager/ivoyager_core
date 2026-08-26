# body_2d_capture_manager.gd
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
class_name IVBody2DCaptureManager
extends Node

## Opens [IVBody2DCaptureDialog] on a hotkey so body 2D icons can be captured from the
## running simulation.
##
## A development tool. It does nothing outside a run from source, because capturing writes
## an [code].import[/code] matching the existing icon set and that has to be read from the
## project's own files (see [IVBody2DIconSaver]). Nothing here ships behavior to an end
## user; the hotkey simply goes unclaimed.

const DIALOG_SCENE := "res://addons/ivoyager_core/ui/body_2d_capture_dialog.tscn"
## Opening size. A [Window] grows past this if its contents demand it, so keep wrapping
## labels in there width-constrained or the dialog inflates to fit one.
const DIALOG_SIZE := Vector2i(880, 620)

## InputMap action that opens the dialog. Set to [code]&""[/code] to disable the hotkey.
var user_action := &"capture_body_2d_icons"

var _dialog: IVBody2DCaptureDialog


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # the hotkey must still work while the sim is paused
	if OS.has_feature("web") or !OS.has_feature("editor"):
		set_process_shortcut_input(false)
		return
	IVStateManager.about_to_free_procedural_nodes.connect(_close_dialog)


func _shortcut_input(event: InputEvent) -> void:
	if !user_action or !IVInputMapManager.is_action_pressed(event, user_action):
		return
	open_dialog()
	get_viewport().set_input_as_handled()


## Opens the capture dialog, building it fresh. Does nothing until the system tree exists,
## since the dialog stages bodies out of the running simulation.
func open_dialog() -> void:
	if _dialog:
		return
	if !IVStateManager.built_system:
		print("IVBody2DCaptureManager: no system tree yet; nothing to capture")
		return
	var packed_scene: PackedScene = load(DIALOG_SCENE)
	_dialog = packed_scene.instantiate() as IVBody2DCaptureDialog
	# Freed rather than hidden on close, and built on demand rather than at startup: the
	# dialog's SubViewport renders on tree membership alone -- there is no visibility gate --
	# so a kept instance would render a 1024² 3D scene every frame for the rest of the session.
	_dialog.visibility_changed.connect(_on_dialog_visibility_changed)
	add_child(_dialog)
	_dialog.popup_centered(DIALOG_SIZE)


func _on_dialog_visibility_changed() -> void:
	if _dialog and !_dialog.visible:
		_close_dialog()


func _close_dialog() -> void:
	if !_dialog:
		return
	_dialog.queue_free()
	_dialog = null
