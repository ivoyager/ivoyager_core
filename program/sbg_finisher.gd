# sbg_finisher.gd
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
class_name IVSBGFinisher
extends RefCounted

## Adds non-persistant [IVSmallBodiesGroup]-associated nodes including orbits
## and points visuals.
##
## Graphic nodes added here are not referenced anywhere else so can be fully
## replaced by modifying script members here. Replacement classes must have
## compatable _init() signatures. (Or, to change that, extend this class in
## [member IVCoreInitializer.program_refcounteds] and override its generator
## methods.)[br][br]
##
## All work here is the same whether this is a new game built from data tables
## or a loaded game built from file.
##
## TODO: Thread build


## Overrides [member IVCoreSettings.use_threads] for this object. THREADS NOT
## IMPLEMENTED FOR THIS CLASS (YET).
var disable_threads := false

var replacement_sbg_orbits_class: Script # replace with any Node3D
var replacement_sbg_points_class: Script # replace with any Node3D


var _tree: SceneTree
var _use_threads: bool


func _init() -> void:
	IVGlobal.project_builder_finished.connect(_on_project_builder_finished)
	_tree = IVGlobal.get_tree()
	_tree.node_added.connect(_on_node_added)


func _on_project_builder_finished() -> void:
	_use_threads = IVCoreSettings.use_threads and !disable_threads


func _on_node_added(node: Node) -> void:
	var sbg := node as IVSmallBodiesGroup
	if !sbg:
		return
	assert(!sbg.is_node_ready(), "Didn't expect IVSmallBodiesGroup to change parents in-game")
	IVGlobal.add_system_tree_item_started.emit(sbg)
	_add_sbg_orbits(sbg)
	_add_sbg_points(sbg)
	IVGlobal.add_system_tree_item_finished.emit(sbg)


func _add_sbg_orbits(sbg: IVSmallBodiesGroup) -> void:
	var sbg_orbits: Node3D
	if replacement_sbg_orbits_class:
		@warning_ignore("unsafe_method_access")
		sbg_orbits = replacement_sbg_orbits_class.new()
	else:
		sbg_orbits = IVSBGOrbits.new(sbg)
	var parent: Node3D = sbg.get_parent()
	parent.add_child(sbg_orbits)


func _add_sbg_points(sbg: IVSmallBodiesGroup) -> void:
	var sbg_points: Node3D
	if replacement_sbg_points_class:
		@warning_ignore("unsafe_method_access")
		sbg_points = replacement_sbg_points_class.new()
	else:
		sbg_points = IVSBGPoints.new(sbg)
	var parent: Node3D = sbg.get_parent()
	parent.add_child(sbg_points)
