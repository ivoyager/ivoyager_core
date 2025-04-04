# sleep_manager.gd
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
class_name IVSleepManager
extends RefCounted

## Optional manager that reduces process load by selectively putting to sleep
## [IVBody] instances that we don't need to process at a given time.
##
## If present, this manager modifies process state for bodies that have
## property `can_sleep == true` (mainly moons and spacecrafts). These bodies
## are processed only when the camera is in their planet system. ("Planet" in
## this context means star orbiting body.)
##
## If this manager is removed, bodies will never sleep.

var _current_planet: IVBody


func _init() -> void:
	IVGlobal.about_to_free_procedural_nodes.connect(_clear)
	IVGlobal.system_tree_ready.connect(_on_system_tree_ready)
	IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)


func _clear() -> void:
	_current_planet = null


func _on_system_tree_ready(_is_new_game: bool) -> void:
	for body in IVBody.top_bodies:
		_set_sleep_recursive(body, true)


func _on_camera_tree_changed(_camera: Camera3D, _parent: Node3D, planet: Node3D, _star: Node3D
		) -> void:
	var to_planet := planet as IVBody
	if _current_planet == to_planet:
		return
	if _current_planet:
		_set_sleep_recursive(_current_planet, true)
	if to_planet:
		_set_sleep_recursive(to_planet, false)
	_current_planet = to_planet


func _set_sleep_recursive(body: IVBody, is_sleep: bool) -> void:
	for satellite in body.satellites:
		satellite.set_sleep(is_sleep) # does nothing if can_sleep == false
		_set_sleep_recursive(satellite, is_sleep)
