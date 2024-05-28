# main_menu_popup.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charlie Whitfield
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
class_name IVMainMenuPopup
extends PopupPanel
const SCENE := "res://addons/ivoyager_core/gui_popups/main_menu_popup.tscn"

## Empty popup that opens/closes on 'ui_cancel' action event and IVGlobal 
## signals.
##
## This base popup is empty. To build a main menu, add a MarginContainer with
## a child VBoxContainer. Then add to that menu buttons. You can find 'state'
## buttons in gui_widgets for: Full Screen, Start, Load, Save, Options,
## Hotkeys, Exit, Quit, Resume and possibly others.

@export var sim_started_only := true
@export var use_theme_manager_setting := true
@export var center := true
@export var stop_sim := true



func _ready() -> void:
	IVGlobal.open_main_menu_requested.connect(open)
	IVGlobal.close_main_menu_requested.connect(close)
	IVGlobal.close_all_admin_popups_requested.connect(close)
	IVGlobal.resume_requested.connect(close)
	popup_hide.connect(_on_popup_hide)
	if use_theme_manager_setting:
		theme = IVGlobal.themes.main_menu


func open() -> void:
	if visible:
		return
	if sim_started_only and !IVGlobal.state.is_started_or_about_to_start:
		return
	if stop_sim:
		IVGlobal.sim_stop_required.emit(self)
	if center:
		popup_centered()
	else:
		popup()


func close() -> void:
	hide()


func _on_popup_hide() -> void:
	if stop_sim:
		IVGlobal.sim_run_allowed.emit(self)

