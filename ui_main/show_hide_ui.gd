# show_hide_gui.gd
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
class_name IVShowHideUI
extends Control

## A parent show/hide Control for UI scene tree construction.
##
## See [IVUniverseTemplate] for scene tree organization.[br][br]
##
## This node hides descendent GUI durring procedural system build and tear-down.
## This can be useful because some widgets build and un-build themselves
## procedurally (e.g., [IVNavButtonsSystem]), which can be ugly during project
## start, exit and quit.[br][br]
##
## It also toggles visibility on [signal IVGlobal.show_hide_gui_requested]
## (this signal isn't emitted by the Core plugin, but is available for project
## use) and on direct call to [method show_hide_gui].[br][br]
##
## It also (optionally) toggles visibility on user key action. See [member
## user_toggle_action].[br][br]

signal visibility_toggled(is_show: bool)

## In most cases, the GUI tree probably shouldn't be persisted. But it might be
## in special cases. This node and [IVTopGUI] have [code]const PERSIST_MODE[/code]
## set to support GUI nodes that have save/load persistence.
const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY


## Set to &"" to disable user key toggle.
@export var user_toggle_action := &"toggle_all_gui"


func _ready() -> void:
	# hide during system build and tear down
	hide()
	set_process_shortcut_input(false)
	IVStateManager.run_state_changed.connect(set_process_shortcut_input) # only when running
	IVStateManager.simulator_started.connect(show)
	IVStateManager.about_to_free_procedural_nodes.connect(hide) # on exit, quit or game load
	IVGlobal.show_hide_gui_requested.connect(show_hide_gui)


func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed(user_toggle_action):
		show_hide_gui()
		get_viewport().set_input_as_handled()


## If [param is_toggle] == true (default), visibility is toggled and the second
## arg [param is_show] is ignored. Use (false, true) to explicitly show or 
## (false, false) to explicitly hide.
func show_hide_gui(is_toggle := true, is_show := true) -> void:
	if not IVStateManager.built_system:
		return
	visible = !visible if is_toggle else is_show
	visibility_toggled.emit(visible)
