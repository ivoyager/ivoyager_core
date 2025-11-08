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
## [member IVBody.flags] == BODYFLAGS_CAN_SLEEP (mainly moons and spacecrafts).
## These bodies are processed only when the camera is in their local "star
## orbiter" system (e.g., at a planet or its moons).[br][br]
##
## If this manager is removed, bodies will never sleep.


var _current_star_orbiter: IVBody


func _init() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVStateManager.system_tree_ready.connect(_on_system_tree_ready)
	IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)



func _clear_procedural() -> void:
	_current_star_orbiter = null


func _on_system_tree_ready(_is_new_game: bool) -> void:
	for body_name in IVBody.galaxy_orbiters:
		_set_sleeping_recursive(IVBody.galaxy_orbiters[body_name], true)


func _on_camera_tree_changed(_camera: Camera3D, _parent: Node3D, star_orbiter: Node3D, _star: Node3D
		) -> void:
	var to_star_orbiter := star_orbiter as IVBody
	if _current_star_orbiter == to_star_orbiter:
		return
	if _current_star_orbiter:
		_set_sleeping_recursive(_current_star_orbiter, true)
	if to_star_orbiter:
		_set_sleeping_recursive(to_star_orbiter, false)
	_current_star_orbiter = to_star_orbiter


func _set_sleeping_recursive(body: IVBody, is_asleep: bool) -> void:
	for satellite_name in body.satellites:
		var satellite := body.satellites[satellite_name]
		satellite.set_sleeping(is_asleep) # does nothing if can_sleep == false
		_set_sleeping_recursive(satellite, is_asleep)
