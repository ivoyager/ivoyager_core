# main_menu_base_popup.gd
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
class_name IVMainMenuBasePopup
extends PopupPanel

## An empty Main Menu popup (base control only) that opens/closes on
## "ui_cancel" action event and "main menu" IVGlobal signals.
##
## This is a base popup upon which you can build a main menu. To build a simple
## menu, add child MarginContainer with child VBoxContainer, then add to that
## your menu buttons. You can find many useful "main menu" buttons in
## directory gui_widgets including [IVFullScreenButton], [IVOptionsButton],
## [IVHotkeysButton], [IVExitButton], [IVQuitButton] and [IVResumeButton].
## Plugin [url=https://github.com/ivoyager/ivoyager_save]I, Voyager - Save[/url]
## has additional save/load related buttons.

const SCENE := "res://addons/ivoyager_core/gui_popups/main_menu_base_popup.tscn"


@export var sim_started_only := true
@export var center := true
@export var stop_sim := true
@export var require_explicit_close := true

var _is_explicit_close := false



func _ready() -> void:
	IVGlobal.open_main_menu_requested.connect(open)
	IVGlobal.close_main_menu_requested.connect(close)
	IVGlobal.close_all_admin_popups_requested.connect(close)
	IVGlobal.resume_requested.connect(close)
	popup_hide.connect(_on_popup_hide)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		close()
		set_input_as_handled()



func open() -> void:
	if visible:
		return
	if sim_started_only and !IVGlobal.state.is_started_or_about_to_start:
		return
	if stop_sim:
		IVGlobal.sim_stop_required.emit(self)
	_is_explicit_close = false
	if center:
		popup_centered()
	else:
		popup()


func close() -> void:
	_is_explicit_close = true
	hide()



func _on_popup_hide() -> void:
	if require_explicit_close and !_is_explicit_close:
		show.call_deferred()
		return
	_is_explicit_close = false
	if stop_sim:
		IVGlobal.sim_run_allowed.emit(self)
