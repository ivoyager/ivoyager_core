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
class_name IVShowHideGUI
extends Control

## Parent "show/hide" Control for GUI scene tree construction.
##
## See [IVUniverseTemplate] for scene tree organization.[br][br]
##
## This node hides GUI durring system build and system tear down (some widgets
## are doing funny stuff then). It also can (optionally) show/hide all
## descendent GUI on user toggle (action: "toggle_all_gui") or on
## [signal IVGlobal.show_hide_gui_requested].[br][br]
##
## In most cases, the GUI tree probably shouldn't be persisted. But it might be
## in special cases. This node and [IVTopGUI] have [code]const PERSIST_MODE[/code]
## to support GUI nodes that have save/load persistence.

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY ## Don't free on load.

@export var on_global_request := true
@export var user_toggle := false


func _ready() -> void:
	# hide during system build and tear down
	hide()
	IVGlobal.simulator_started.connect(show)
	IVGlobal.about_to_free_procedural_nodes.connect(hide) # on exit or game load
	if on_global_request:
		IVGlobal.show_hide_gui_requested.connect(show_hide_gui)
	set_process_unhandled_key_input(user_toggle)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_all_gui"):
		show_hide_gui()
		get_viewport().set_input_as_handled()


func show_hide_gui(is_toggle := true, is_show := true) -> void:
	if not IVStateManager.is_system_built:
		return
	visible = !visible if is_toggle else is_show
