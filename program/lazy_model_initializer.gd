# lazy_model_initializer.gd
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
class_name IVLazyModelInitializer
extends RefCounted

## Optional manager for lazy model instantiation.
##
## If this manager is present, bodies with `lazy_model == true` table value
## will have no [IVModelSpace] (and thus no model) at simulation start. Once
## visited, the lazy model is instantiated and remains for the rest of the user
## session. This is useful for large models (like the ISS) and 100+ tiny remote
## moons and asteroids that may never be visited in a given user session.[br][br]
##
## If this manager is removed, all lazy models will be instantiated during
## solar system build.[br][br]
##
## See also [IVSleepManager] for reduction of IVBody._process() calls where not
## needed.

# TOTO: Rename IVLazyModelInitializer

func _init() -> void:
	IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)


func _on_camera_tree_changed(_camera: Camera3D, parent: Node3D, _star_orbiter: Node3D, _star: Node3D
		) -> void:
	var body := parent as IVBody
	if !body or !body.is_lazy_model_uninited():
		return
	body.lazy_model_init()
	
	# It's rare that a lazy model body has a satellite or a lazy parent
	# (because bodies with satellites are large), but we test here just in case.
	# One example might be a remote dwarf planet with moons.
	_lazy_init_down(body)
	_lazy_init_up(body)


func _lazy_init_down(body: IVBody) -> void:
	for satellite in body.satellites:
		if satellite.is_lazy_model_uninited():
			satellite.lazy_model_init()
			_lazy_init_down(satellite)


func _lazy_init_up(body: IVBody) -> void:
	var parent := body.get_parent_node_3d() as IVBody
	if parent and parent.is_lazy_model_uninited():
		parent.lazy_model_init()
		_lazy_init_down(parent) # cousins?
		_lazy_init_up(parent)
