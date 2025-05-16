# body_finisher.gd
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
class_name IVBodyFinisher
extends RefCounted

## Adds non-persistant nodes to IVBody instances including a model, rings,
## lights, and HUD elements (as applicable).
##
## All work here is the same whether this is a new game built from data tables
## or a loaded game built from file. Most of the work is done on threads if
## IVCoreSettings.use_threads == true.[br][br]
##
## All nodes instantiated here are either base Godot class or class defined in
## IVCoreInitializer.procedural_classes. Procedural class replacements are ok
## as long as init signature is compatible.

const files := preload("res://addons/ivoyager_core/static/files.gd")
const BodyFlags := IVBody.BodyFlags

var _use_threads := IVCoreSettings.use_threads
var _tree: SceneTree


func _init() -> void:
	_tree = IVGlobal.get_tree()
	_tree.node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	var body := node as IVBody
	if !body or body.is_node_ready(): # skip if body is just changing parent
		return
	IVGlobal.add_system_tree_item_started.emit(body) # increments IVStateManager counter
	
	if _use_threads:
		WorkerThreadPool.add_task(_finish.bind(body))
	else:
		_finish.call_deferred(body)


func _finish(body: IVBody) -> void:
	# Everything here must be thread-safe!
	var children: Array[Node] = []
	var siblings: Array[Node] = []
	var model_space_nodes: Array[Node3D] = []
	
	_get_body_label(body, children)
	
	if body.has_orbit():
		_get_orbit_visual(body, siblings)
	if body.has_light():
		_get_dynamic_light(body, children)
		_get_omni_lights(body, children)
	if body.has_rings():
		_get_rings(body, model_space_nodes)
	
	_deffered_finish.call_deferred(body, children, siblings, model_space_nodes)


func _deffered_finish(body: IVBody, children: Array[Node], siblings: Array[Node],
		model_space_nodes: Array[Node3D]) -> void:
	# Main thread.
	for node in children:
		body.add_child(node)
	for node in siblings:
		body.get_parent().add_child(node)
	for node3d in model_space_nodes:
		body.add_child_to_model_space(node3d)
	await _tree.process_frame
	IVGlobal.add_system_tree_item_finished.emit(body) # decrements IVStateManager counter


# *****************************************************************************
# All below happen on thread...


func _get_body_label(body: IVBody, children: Array[Node]) -> void:
	var body_label_script: Script = IVGlobal.procedural_classes[&"BodyLabel"]
	@warning_ignore("unsafe_method_access")
	var body_label: Label3D = body_label_script.new(body, IVCoreSettings.body_labels_color,
			IVCoreSettings.body_labels_use_orbit_color)
	children.append(body_label)


func _get_orbit_visual(body: IVBody, siblings: Array[Node]) -> void:
	var orbit_visual_script: Script = IVGlobal.procedural_classes[&"OrbitVisual"]
	@warning_ignore("unsafe_method_access")
	var orbit_visual: Node = orbit_visual_script.new(body)
	siblings.append(orbit_visual)


func _get_dynamic_light(body: IVBody, children: Array[Node]) -> void:
	# Adds the "top" IVDynamicLight if applicable (the top light adds child
	# dynamic lights). Does not add if IVCoreSettings.dynamic_lights == false.
	if !IVCoreSettings.dynamic_lights:
		return
	var body_name := body.name
	var dynamic_light_script: Script = IVGlobal.procedural_classes[&"DynamicLight"]
	@warning_ignore("unsafe_method_access")
	var dynamic_light: Node = dynamic_light_script.new(body_name)
	children.append(dynamic_light)


func _get_omni_lights(body: IVBody, children: Array[Node]) -> void:
	# Adds OmniLight3D(s) built entirely from omni_lights.tsv if applicable. By
	# default, omni_light.tsv rows have disable_if_dynamic_enabled == true, so
	# are not added if IVCoreSettings.dynamic_lights == true. May add >1 light
	# if specified in table.
	var body_name := body.name
	for row in IVTableData.get_n_rows(&"omni_lights"):
		if (IVCoreSettings.dynamic_lights and
				IVTableData.get_db_bool(&"omni_lights", &"disable_if_dynamic_enabled", row)):
			continue
		var bodies: Array[StringName] = IVTableData.get_db_array(&"omni_lights", &"bodies", row)
		if !bodies.has(body_name):
			continue
		var omni_light := OmniLight3D.new()
		IVTableData.db_build_object(omni_light, &"omni_lights", row)
		children.append(omni_light)


func _get_rings(body: IVBody, model_space_nodes: Array[Node3D]) -> void:
	# See IVRings for resource requirements.
	var rings_script: Script = IVGlobal.procedural_classes[&"Rings"]
	@warning_ignore("unsafe_method_access")
	var rings: Node3D = rings_script.new(body)
	model_space_nodes.append(rings)
