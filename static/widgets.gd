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

## Static utility methods for GUI widgets.


# Notes on static vars:
# No Callables or Signals are stored.
# All Nodes treated as if they can become invalid at any time.
# All procedural references are nulled on IVStateManager.about_to_free_procedural_nodes.
static var _selection_widgets: Array[Array] = []
static var _ivcamera_widgets: Array[Array] = []
static var _ivcamera: IVCamera 



## Call once when [param widget] is in the scene tree, e.g., in _ready() method.[br][br]
##
## Expects each widget to have an ancestor Control with property [param
## selection_manager] set before IVStateManager.system_tree_ready).
static func connect_selection_manager(widget: Control, changed_callback := &"",
		connection_pairs: Array[StringName] = []) -> void:
	assert(widget.is_inside_tree())
	assert(changed_callback or connection_pairs,
			"Method needs 'changed_callback' or 'connection_pairs' to do anything")
	assert(!changed_callback or widget.has_method(changed_callback),
			"Widget does not have changed_callback method: '%s'" % changed_callback)
	assert(connection_pairs.size() % 2 == 0, "'connection_pairs' must be an even number size")
	for i in range(0, connection_pairs.size(), 2):
		var widget_method: StringName = connection_pairs[i + 1]
		assert(widget.has_method(widget_method),
				"Widget does not have method in connection_pairs: '%s'" % widget_method)
		# We assert valid signal when we have a camera in _disconnect_connect_ivcamera().
	if not IVStateManager.about_to_free_procedural_nodes.is_connected(_on_about_to_free_procedural_nodes):
		IVStateManager.about_to_free_procedural_nodes.connect(_on_about_to_free_procedural_nodes)
	if not IVStateManager.system_tree_ready.is_connected(_on_system_tree_ready):
		IVStateManager.system_tree_ready.connect(_on_system_tree_ready)
	var selection_manager: IVSelectionManager = null
	if IVStateManager.system_tree_ready:
		selection_manager = IVSelectionManager.get_selection_manager(widget)
	_selection_widgets.append([widget, changed_callback, connection_pairs, selection_manager])
	if selection_manager:
		_disconnect_connect_selection_manager(widget, changed_callback, connection_pairs,
				null, selection_manager)


## Call once when [param widget] is in the scene tree, e.g., in _ready() method.[br][br]
## 
## If [param changed_callback] is specified, when a new IVCamera becomes
## current (or if one already is current) a callback to this method will
## occur with camera as the single argument. The callback will be called with
## null as argument when procedural objects are freed on quit, exit, or game
## load, or if [signal IVGlobal.camera_ready] specifies a Camera3D that is not
## an IVCamera.[br][br]
##
## [param connection_pairs] can contain any number of camera_signal / widget_method
## pairs, all as StringName. Each camera signal will be connected to / disconnected
## from the paired widget method as needed.[br][br]
##
## This method can take any Node as [param widget].
## @experimental
static func connect_ivcamera(widget: Node, changed_callback := &"",
		connection_pairs: Array[StringName] = []) -> void:
	assert(widget.is_inside_tree())
	assert(changed_callback or connection_pairs,
			"Method needs 'changed_callback' or 'connection_pairs' to do anything")
	assert(!changed_callback or widget.has_method(changed_callback),
			"Widget does not have changed_callback method: '%s'" % changed_callback)
	assert(connection_pairs.size() % 2 == 0, "'connection_pairs' must be an even number size")
	for i in range(0, connection_pairs.size(), 2):
		var widget_method: StringName = connection_pairs[i + 1]
		assert(widget.has_method(widget_method),
				"Method '%s' does not exist in %s" % [widget_method, widget])
		# We assert valid signal when we have a camera in _disconnect_connect_ivcamera().
	if not IVStateManager.about_to_free_procedural_nodes.is_connected(_on_about_to_free_procedural_nodes):
		IVStateManager.about_to_free_procedural_nodes.connect(_on_about_to_free_procedural_nodes)
	if not IVGlobal.camera_ready.is_connected(_set_current_ivcamera):
		IVGlobal.camera_ready.connect(_set_current_ivcamera)
	_ivcamera_widgets.append([widget, changed_callback, connection_pairs])
	var camera := widget.get_tree().get_root().get_camera_3d() as IVCamera
	assert(camera == _ivcamera, "Inconsistent widget cameras. Core bug?") # nulls before camera added
	if camera:
		_disconnect_connect_ivcamera(widget, changed_callback, connection_pairs, null)



static func _on_system_tree_ready(_new_game: bool) -> void:
	_set_selection_managers(false)


static func _on_about_to_free_procedural_nodes() -> void:
	if IVStateManager.quitting: # skip the work below
		_selection_widgets.clear()
		_ivcamera_widgets.clear()
		return
	# Calls below null procedural references and disconnect signals (here and
	# in widgets) on exit and game load.
	_set_selection_managers(true)
	_set_current_ivcamera(null)


static func _set_selection_managers(force_null: bool) -> void:
	var i := _selection_widgets.size() - 1
	while i >= 0:
		var array := _selection_widgets[i]
		if not is_instance_valid(array[0]):
			_selection_widgets.remove_at(i)
			i -= 1
			continue
		var widget: Control = array[0]
		var changed_callback: StringName = array[1]
		var connection_pairs: Array[StringName] = array[2]
		var last_manager: IVSelectionManager = null
		if is_instance_valid(array[3]):
			last_manager = array[3]
		var new_manager: IVSelectionManager = null
		if not force_null:
			new_manager = IVSelectionManager.get_selection_manager(widget)
		array[3] = new_manager
		_disconnect_connect_selection_manager(widget, changed_callback, connection_pairs,
				last_manager, new_manager)
		i -= 1


static func _disconnect_connect_selection_manager(widget: Control, changed_callback: StringName,
		connection_pairs: Array[StringName], last_manager: IVSelectionManager,
		new_manager: IVSelectionManager) -> void:
	if changed_callback:
		widget.call(changed_callback, new_manager)
	for i in range(0, connection_pairs.size(), 2):
		var manager_signal: StringName = connection_pairs[i]
		var widget_method: StringName = connection_pairs[i + 1]
		var callable := Callable(widget, widget_method)
		if last_manager:
			last_manager.disconnect(manager_signal, callable)
		if new_manager:
			assert(new_manager.has_signal(manager_signal),
					"Attempt to connect IVSelectionManager signal that does not exist: '%s'" %
					manager_signal)
			new_manager.connect(manager_signal, callable)


static func _set_current_ivcamera(camera3d: Camera3D) -> void:
	var last_camera: IVCamera = null
	if is_instance_valid(_ivcamera):
		last_camera = _ivcamera
	_ivcamera = camera3d as IVCamera # null ok for _ivcamera or camera3d
	var i := _ivcamera_widgets.size() - 1
	while i >= 0:
		var array := _ivcamera_widgets[i]
		if not is_instance_valid(array[0]):
			_ivcamera_widgets.remove_at(i)
			i -= 1
			continue
		var widget: Node = array[0]
		var changed_callback: StringName = array[1]
		var connection_pairs: Array[StringName] = array[2]
		_disconnect_connect_ivcamera(widget, changed_callback, connection_pairs, last_camera)
		i -= 1


static func _disconnect_connect_ivcamera(widget: Node, changed_callback: StringName,
		connection_pairs: Array[StringName], last_camera: IVCamera) -> void:
	if changed_callback:
		widget.call(changed_callback, _ivcamera)
	for i in range(0, connection_pairs.size(), 2):
		var camera_signal: StringName = connection_pairs[i]
		var widget_method: StringName = connection_pairs[i + 1]
		var callable := Callable(widget, widget_method)
		if last_camera:
			last_camera.disconnect(camera_signal, callable)
		if _ivcamera:
			assert(_ivcamera.has_signal(camera_signal),
					"Attempt to connect IVCamera signal that does not exist: '%s'" % camera_signal)
			_ivcamera.connect(camera_signal, callable)
