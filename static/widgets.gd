# widgets.gd
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
class_name IVWidgets
extends Object

## TODO: TEST and implement. Make another for IVSelectionManager
## @experimental
static func connect_camera(widget: Control, property: StringName, connection_pairs := []) -> void:
	assert(connection_pairs.size() % 2 == 0, "'connection_pairs' must be an even number size")
	for i in range(0, connection_pairs.size(), 2):
		assert(connection_pairs[i] is StringName,
				"'connection_pairs' must contain StringName, Callable pairs")
		assert(connection_pairs[i + 1] is Callable,
				"'connection_pairs' must contain StringName, Callable pairs")
	IVGlobal.camera_ready.connect(_connect_camera.bind(widget, property, connection_pairs))
	var camera := widget.get_viewport().get_camera_3d() as IVCamera
	if camera:
		_connect_camera(camera, widget, property, connection_pairs)


static func _connect_camera(camera3d: Camera3D, widget: Control, property: StringName,
		connection_pairs: Array) -> void:
	var camera := camera3d as IVCamera
	if not is_instance_valid(widget):
		return
	if property:
		var previous_camera: IVCamera = widget.get(property)
		if previous_camera:
			_disconnect_camera(camera, widget, property, connection_pairs)
		widget.set(property, camera)
	if not camera:
		return
	for i in range(0, connection_pairs.size(), 2):
		var camera_signal: StringName = connection_pairs[i]
		var callable: Callable = connection_pairs[i + 1]
		camera.connect(camera_signal, callable)
	IVStateManager.about_to_free_procedural_nodes.connect(_disconnect_camera.bind(camera,
			widget, property, connection_pairs))


static func _disconnect_camera(camera: IVCamera, widget: Control, property: StringName,
		connection_pairs: Array) -> void:
	if not is_instance_valid(widget):
		return
	if property:
		widget.set(property, null)
	if !camera or !is_instance_valid(camera):
		return
	for i in range(0, connection_pairs.size(), 2):
		var camera_signal: StringName = connection_pairs[i]
		var callable: Callable = connection_pairs[i + 1]
		
		# TEST: Do we need to unbind args from callable?
		
		camera.disconnect(camera_signal, callable)
	
	
