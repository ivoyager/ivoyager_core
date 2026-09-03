# shader_warmup.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
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
class_name IVShaderWarmup
extends Node

## Draws every spatial shader in [member IVGlobal.resources] under a loading or
## splash screen, so the first visit to a body does not stall on the GPU driver.
##
## The GL renderer compiles a shader program the first time it is drawn,
## synchronously, on the main thread, and a program is compiled per light-mask
## and shadow-pass specialization. A stall of seconds in flight is a defect; the
## same stall under a loading screen is a progress message. This node draws each
## shader on a small quad in front of the camera, one shader per frame, at a
## planet-scale layer and at a craft-scale, shadow-casting layer. A program the
## opening view has already drawn costs nothing here, and a repeat run answers
## from the driver's cache in a frame per shader.[br][br]
##
## Opt in by adding this class to [member IVCoreInitializer.program_nodes], and
## set [member trigger] for the project's boot sequence (from
## [signal IVStateManager.core_init_program_objects_instantiated], before this
## node is added to the tree). The screen that covers the warm-up should stay up
## until [signal finished] rather than [signal IVStateManager.simulator_started],
## and can display [signal progress_changed]: it is emitted one frame before the
## draw that may stall, so the text a handler sets is the text that stays on
## screen through the stall.[br][br]
##
## See [code]SHADER_COMPILE_COST.md[/code] for what a compile costs, what drives
## it, and what a cold start measures.

## Emitted one frame before shader [param index] (0-based, of [param count]) is
## first drawn; [param shader_name] is its key in [member IVGlobal.resources].
signal progress_changed(index: int, count: int, shader_name: StringName)
## Emitted when every shader has been drawn, or at once if the warm-up is skipped.
signal finished()


## When the warm-up runs. See [member trigger].
enum Trigger {
	## On [signal IVStateManager.simulator_started]. The system tree exists and
	## [IVCamera] has processed, so the quads draw in the real scene and compile
	## the base, additive and shadow specializations bodies use. For a project
	## that boots straight into the simulator behind a loading screen.
	SIMULATOR_STARTED,
	## On [signal IVStateManager.assets_preloaded], which is where a splash-screen
	## project ([member IVCoreSettings.wait_for_start] == true) waits for the user
	## to start. No system tree exists yet, so the warm-up supplies its own camera
	## and light. It gets the larger, scene-independent part of every shader: the
	## four variants at the default specialization mask, over half of what a first
	## draw costs. The specializations the scene itself selects still compile when
	## a body is first drawn, so this trades a smaller residual stall for a warm-up
	## the user can watch. Gate the splash screen's start button on
	## [signal finished] to keep even that off the user's flight.
	ASSETS_PRELOADED,
	## Never on its own; the project calls [method warm_up].
	MANUAL,
}

const QUAD_DISTANCE_MULTIPLIER := 4.0 ## quad distance, as a multiple of the camera's near
const QUAD_SIZE_FRACTION := 0.02 ## quad width, as a fraction of its distance
const SETTLE_FRAMES := 2 ## frames a quad is left to draw before the next shader

## When the warm-up runs. Set before this node enters the tree.
var trigger := Trigger.SIMULATOR_STARTED
## Skip the warm-up under the Forward+ and Mobile renderers, where a compile
## costs a tenth of what it does under Compatibility.
var gl_compatibility_only := false
## Body mean radii whose size layers the quads take (see
## [member IVCoreSettings.size_layers]); the last also carries
## [constant IVGlobal.LOCAL_SHADOW_CASTER]. Each distinct layer value is one
## more draw of every shader.
var warm_radii: Array[float] = [1e4 * IVUnits.KM, 0.01 * IVUnits.KM]

var _running := false
var _quads: Array[MeshInstance3D] = []
var _temporary_rig: Node3D


func _ready() -> void:
	match trigger:
		Trigger.SIMULATOR_STARTED:
			IVStateManager.simulator_started.connect(warm_up)
		Trigger.ASSETS_PRELOADED:
			IVStateManager.assets_preloaded.connect(warm_up)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)


## Draws every shader once, emitting [signal progress_changed] as it goes and
## [signal finished] when it is done. Called by [member trigger]; call it
## directly for [constant Trigger.MANUAL]. Does nothing if already running.
func warm_up() -> void:
	if _running:
		return
	if gl_compatibility_only and !IVGlobal.is_gl_compatibility:
		finished.emit()
		return
	_running = true
	_run()


func _run() -> void:
	# After simulator_started, IVCamera shifts the origin and sets its near and
	# far in its first processed frame; before that it is nowhere we can draw.
	await get_tree().process_frame
	await get_tree().process_frame
	var start_msec := Time.get_ticks_msec()
	var shader_names := _get_spatial_shader_names()
	var camera := get_viewport().get_camera_3d()
	if !camera:
		camera = _add_temporary_rig()
	if !shader_names.is_empty():
		var layers := _get_layers()
		var count := shader_names.size()
		for index in count:
			if !_running: # cancelled by _clear_procedural()
				break
			var shader_name := shader_names[index]
			var shader: Shader = IVGlobal.resources[shader_name]
			progress_changed.emit(index, count, shader_name)
			await get_tree().process_frame # the frame that shows the message
			if !_running or !is_instance_valid(camera):
				break
			for layer in layers:
				_add_quad(camera, shader, layer)
			for _frame in SETTLE_FRAMES:
				await get_tree().process_frame
	_free_added_nodes()
	if !_running:
		return
	print("Shader warm-up: %d shaders in %.1f s" % [shader_names.size(),
			(Time.get_ticks_msec() - start_msec) / 1000.0])
	_running = false
	finished.emit()


func _clear_procedural() -> void:
	_free_added_nodes()
	_running = false


func _get_spatial_shader_names() -> Array[StringName]:
	# Sky shaders can't go on a mesh, and canvas shaders have no reason to.
	var shader_names: Array[StringName] = []
	for key: StringName in IVGlobal.resources:
		var resource: Resource = IVGlobal.resources[key]
		var shader := resource as Shader
		if shader and shader.get_mode() == Shader.MODE_SPATIAL:
			shader_names.append(key)
	return shader_names


func _get_layers() -> Array[int]:
	if !IVCoreSettings.apply_size_layers:
		return [1]
	var layers: Array[int] = []
	var last_index := warm_radii.size() - 1
	for index in warm_radii.size():
		var layer := IVCoreSettings.get_visualinstance3d_layer_for_size(warm_radii[index])
		if index == last_index:
			layer |= IVGlobal.LOCAL_SHADOW_CASTER
		if !layers.has(layer):
			layers.append(layer)
	return layers


func _add_temporary_rig() -> Camera3D:
	# Before the system tree is built there is no camera to draw through and no
	# light to be drawn by, and a shader compiles a different specialization
	# unlit than lit. One unshadowed directional light gives the base pass the
	# same light bits a body's own draw has. Nothing else is current, so this
	# steals no view, and both nodes go away with the quads.
	_temporary_rig = Node3D.new()
	add_child(_temporary_rig)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = false
	_temporary_rig.add_child(light)
	var camera := Camera3D.new()
	_temporary_rig.add_child(camera)
	camera.current = true
	return camera


func _add_quad(camera: Camera3D, shader: Shader, layers: int) -> void:
	var material := ShaderMaterial.new()
	material.shader = shader
	var mesh := QuadMesh.new()
	var distance := camera.near * QUAD_DISTANCE_MULTIPLIER
	mesh.size = Vector2.ONE * distance * QUAD_SIZE_FRACTION
	var quad := MeshInstance3D.new()
	quad.mesh = mesh
	quad.material_override = material
	quad.layers = layers
	quad.position = Vector3(0.0, 0.0, -distance)
	camera.add_child(quad)
	_quads.append(quad)


func _free_added_nodes() -> void:
	for quad in _quads:
		if is_instance_valid(quad):
			quad.queue_free()
	_quads.clear()
	if is_instance_valid(_temporary_rig):
		_temporary_rig.queue_free()
	_temporary_rig = null
