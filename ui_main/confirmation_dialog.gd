# confirmation_dialog.gd
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
class_name IVConfirmationDialog
extends ConfirmationDialog

## A single ConfirmationDialog for all user confirmations
##
## Call using [signal IVGlobal.confirmation_requested]. Calling with
## [param stop_sim] == true (default) means that the sim will stop while the
## dialog is open. This can be suppressed by setting
## [member IVCoreSettings.popops_can_stop_sim] to false.

var _stop_sim: bool
var _action: Callable


func _ready() -> void:
	IVGlobal.confirmation_requested.connect(_on_confirmation_requested)
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)
	focus_exited.connect(_retake_focus)
	get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		set_input_as_handled()


func _on_confirmation_requested(text: StringName, action: Callable, stop_sim := true,
		title_txt := &"LABEL_PLEASE_CONFIRM", ok_txt := &"BUTTON_OK", cancel_txt := &"BUTTON_CANCEL"
		) -> void:
	if visible:
		push_warning("Confirmation requested when already open")
		# Discard/overwrite existing dialog. Avoid edge case permanent stop.
		if _stop_sim and !stop_sim:
			IVStateManager.allow_run(self)
	_stop_sim = stop_sim and IVCoreSettings.popops_can_stop_sim
	_action = action
	dialog_text = text
	title = title_txt
	ok_button_text = ok_txt
	cancel_button_text = cancel_txt
	if _stop_sim:
		IVStateManager.require_stop(self)
	popup_centered()
	_retake_focus()


func _on_confirmed() -> void:
	if _stop_sim:
		IVStateManager.allow_run(self)
	_action.call()


func _on_canceled() -> void:
	if _stop_sim:
		IVStateManager.allow_run(self)


func _retake_focus() -> void:
	await get_tree().process_frame
	if !has_focus():
		grab_focus()
