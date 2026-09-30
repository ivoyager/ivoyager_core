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

## Draws the spatial shaders a project will actually use, under a loading or splash
## screen, so the first visit to a body does not stall on the GPU driver.
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
## What it draws comes from two places. Core's own shaders are selected from the tables
## and the loaded assets ([member warm_core_shaders]): a body's shell shaders from the
## specs [IVAssetPreloader] has already resolved, which is exact and picks up a project's
## own shader named in a [code]shells.tsv[/code] [code]shader[/code] cell; and the rest on
## the same conditions [IVBodyFinisher] and [IVSBGFinisher] apply when they add the node
## that binds one. A shader no such condition can decide is deliberately NOT warmed, since
## a needless compile is seconds of loading screen — name it in
## [member extra_shader_names], which is also where a project's own shaders go.
## [code]stars_shader[/code] is the one Core shader in that position: [IVStarsVisual] is a
## scene node, so nothing in the tables says whether the project kept it. Under the default
## trigger the star field is in the opening view and has compiled before this node runs
## anyway. After the shaders it draws the materials of each body's packed model, such as a
## spacecraft's, one model per frame ([member warm_packed_models]).[br][br]
##
## Opt in by adding this class to [member IVCoreInitializer.program_nodes], and
## set [member trigger] for the project's boot sequence (from
## [signal IVStateManager.core_init_program_objects_instantiated], before this
## node is added to the tree). Under either automatic trigger the warm-up holds
## [IVStateManager]'s startup state until [signal finished], so a splash or boot
## screen that follows [member IVStateManager.show_splash_screen] and
## [member IVStateManager.ok_to_start] covers it with no wiring of its own. It
## runs once per session; a later new or loaded game finds its shaders compiled.
## The screen can display [signal progress_changed]: it is emitted one frame
## before the draw that may stall, so the text a handler sets is the text that
## stays on screen through the stall.[br][br]
##
## See [i]Compiling shaders[/i] in [code]GRAPHICS_PROFILING.md[/code] for what a
## compile costs, what drives it, and what a cold start measures.

## Emitted one frame before step [param index] (0-based, of [param count]) is first
## drawn. [param step_name] is a shader's key in [member IVGlobal.resources], or for a
## packed model's materials the first body that uses the model.
signal progress_changed(index: int, count: int, step_name: StringName)
## Emitted when every shader has been drawn, or at once if the warm-up is skipped,
## after the warm-up has released its hold on [IVStateManager].
signal finished()


## When the warm-up runs. See [member trigger].
enum Trigger {
	## On [signal IVStateManager.simulator_started]. The system tree exists and
	## [IVCamera] has processed, so the quads draw in the real scene and compile
	## the base, additive and shadow specializations bodies use.
	## [member IVStateManager.show_splash_screen] stays true until [signal finished],
	## so the screen that covered the system build, whether a boot screen or a
	## splash screen after its start button, stays up for the warm-up too.
	SIMULATOR_STARTED,
	## On [signal IVStateManager.assets_preloaded], which is where a splash-screen
	## project ([member IVCoreSettings.wait_for_start] == true) waits for the user
	## to start. No system tree exists yet, so the warm-up supplies its own camera
	## and light. It gets the larger, scene-independent part of every shader: the
	## four variants at the default specialization mask, over half of what a first
	## draw costs. The specializations the scene itself selects still compile when
	## a body is first drawn, so this trades a smaller residual stall for a warm-up
	## the user can watch. [member IVStateManager.ok_to_start] stays false until
	## [signal finished], so neither [IVStartButton] nor a gamesave load can
	## build a system tree over it.
	ASSETS_PRELOADED,
	## Never on its own; the project calls [method warm_up] and covers it itself,
	## e.g. with [method IVStateManager.hold_start] or
	## [method IVStateManager.hold_splash_screen].
	MANUAL,
}

const QUAD_DISTANCE_MULTIPLIER := 4.0 ## quad distance, as a multiple of the camera's near
const QUAD_SIZE_FRACTION := 0.02 ## quad width, as a fraction of its distance
const SETTLE_FRAMES := 2 ## frames a step's quads are left to draw before the next step

## When the warm-up runs. Set before this node enters the tree.
var trigger := Trigger.SIMULATOR_STARTED
## Skip the warm-up under the Forward+ and Mobile renderers, where a compile
## costs a tenth of what it does under Compatibility.
var gl_compatibility_only := false
## Whether Core's own shaders are selected automatically (see the class description).
## Set false to take full control through [member extra_shader_names].
var warm_core_shaders := true
## Additional shaders to warm, as keys in [member IVGlobal.resources]: a project's own
## spatial shaders, and any Core shader the automatic selection leaves out. A key naming
## no [Shader], or naming a non-spatial one, warns and is skipped.
var extra_shader_names: Array[StringName] = []
## Whether the materials of each body's packed model
## ([method IVAssetPreloader.get_body_packed_model]) are drawn, one model per step.
var warm_packed_models := true
## Body mean radii whose size layers the quads take (see
## [member IVCoreSettings.size_layers]); the last also carries
## [constant IVGlobal.LOCAL_SHADOW_CASTER]. Each distinct layer value is one
## more draw of every shader.
var warm_radii: Array[float] = [1e4 * IVUnits.KM, 0.01 * IVUnits.KM]

var _running := false
var _quads: Array[MeshInstance3D] = []
var _temporary_rig: Node3D
var _shadow_geometry_camera: Camera3D


func _ready() -> void:
	# IVStateManager sets the state a hold keeps immediately before it emits the
	# trigger, so the hold is taken now.
	match trigger:
		Trigger.SIMULATOR_STARTED:
			IVStateManager.hold_splash_screen(self)
			IVStateManager.simulator_started.connect(warm_up)
		Trigger.ASSETS_PRELOADED:
			IVStateManager.hold_start(self)
			IVStateManager.assets_preloaded.connect(warm_up)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)


## Draws every shader once, emitting [signal progress_changed] as it goes and
## [signal finished] when it is done. Called by [member trigger]; call it
## directly for [constant Trigger.MANUAL]. Does nothing if already running.
func warm_up() -> void:
	if _running:
		return
	if gl_compatibility_only and !IVGlobal.is_gl_compatibility:
		_finish()
		return
	_running = true
	_run()


func _run() -> void:
	# After simulator_started, IVCamera shifts the origin and sets its near and
	# far in its first processed frame; before that it is nowhere we can draw.
	await get_tree().process_frame
	await get_tree().process_frame
	var start_msec := Time.get_ticks_msec()
	var step_names: Array[StringName] = []
	var step_materials: Array[Array] = [] # an Array[Material] per step
	_add_shader_steps(step_names, step_materials)
	var shader_count := step_names.size()
	if warm_packed_models:
		_add_packed_model_steps(step_names, step_materials)
	var camera := get_viewport().get_camera_3d()
	if !camera:
		camera = _add_temporary_rig()
	# The quads are the only geometry a warm-up frame has, and they are not bodies, so the
	# sweep behind IVCoreSettings.apply_empty_shadow_pass_skip cannot see them: a light
	# whose domain they leave empty would switch its map off and the remaining shaders would
	# compile a shadowed-light count the app never runs. Declaring them keeps the whole
	# stack live. Distance is the quads' own, since _add_quad parents them to the camera.
	_shadow_geometry_camera = camera
	var all_size_domains := (1 << IVCoreSettings.get_size_domain_count()) - 1
	IVDynamicLight.add_local_shadow_geometry(camera,
			all_size_domains | IVGlobal.LOCAL_SHADOW_CASTER)
	if !step_names.is_empty():
		var layers := _get_layers()
		var count := step_names.size()
		for index in count:
			if !_running: # cancelled by _clear_procedural()
				break
			progress_changed.emit(index, count, step_names[index])
			await get_tree().process_frame # the frame that shows the message
			if !_running or !is_instance_valid(camera):
				break
			for material: Material in step_materials[index]:
				for layer in layers:
					_add_quad(camera, material, layer)
			for _frame in SETTLE_FRAMES:
				await get_tree().process_frame
	_free_added_nodes()
	if !_running:
		return
	print("Shader warm-up: %d shaders and %d models in %.1f s" % [shader_count,
			step_names.size() - shader_count, (Time.get_ticks_msec() - start_msec) / 1000.0])
	_running = false
	_finish()


func _finish() -> void:
	# Every new or loaded game emits simulator_started again, and a repeat would
	# hold the splash screen over shaders this session has already compiled.
	if IVStateManager.simulator_started.is_connected(warm_up):
		IVStateManager.simulator_started.disconnect(warm_up)
	IVStateManager.release_start(self)
	IVStateManager.release_splash_screen(self)
	finished.emit()


func _clear_procedural() -> void:
	_free_added_nodes()
	_running = false
	# assets_preloaded never comes again to retry a cancelled warm-up, so it must
	# not go on holding the start. A splash-screen hold stays for the retry at the
	# next simulator_started.
	IVStateManager.release_start(self)


func _add_shader_steps(step_names: Array[StringName], step_materials: Array[Array]) -> void:
	for shader_name in _get_shader_names():
		var shader: Shader = IVGlobal.resources[shader_name]
		var material := ShaderMaterial.new()
		material.shader = shader
		step_names.append(shader_name)
		step_materials.append([material])


func _get_shader_names() -> Array[StringName]:
	var shader_names: Array[StringName] = []
	if warm_core_shaders:
		_add_shell_shaders(shader_names)
		_add_body_node_shaders(shader_names)
		_add_small_bodies_shaders(shader_names)
	for shader_name in extra_shader_names:
		_add_shader_name(shader_names, shader_name, true)
	return shader_names


func _add_shell_shaders(shader_names: Array[StringName]) -> void:
	# Every shader IVShellsModel will bind, read off the specs IVAssetPreloader resolved at
	# load — cubemap variants included, and a project's own shader with them. The scene tree
	# cannot answer this: a body's visual is built lazily, on the camera's first visit, which
	# is the very stall being warmed against.
	var asset_preloader: IVAssetPreloader = IVGlobal.program.get(&"AssetPreloader")
	if !asset_preloader:
		return
	for table in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table):
			var body_name := IVTableData.get_db_entity_name(table, row)
			for shell_spec: Dictionary in asset_preloader.get_body_shell_specs(body_name):
				var shader_name: StringName = shell_spec[&"shader"]
				if shader_name: # else the shell takes a StandardMaterial3D
					_add_shader_name(shader_names, shader_name, false)


func _add_body_node_shaders(shader_names: Array[StringName]) -> void:
	# The per-body nodes IVBodyFinisher adds, on the conditions it applies there. Unlike a
	# body's shells these are not lazy, so each draws as soon as its body is built.
	if IVBodyPSF.is_applicable_to_any_body():
		_add_shader_name(shader_names, &"body_psf_shader", false)
	if _any_body_has_rings():
		_add_shader_name(shader_names, &"rings_shader", false)
	if _any_body_orbits():
		_add_shader_name(shader_names, &"path_shader", false)
		if IVGlobal.program.has(&"FragmentIdentifier"): # absent under Compatibility
			_add_shader_name(shader_names, &"path_id_shader", false)


func _add_small_bodies_shaders(shader_names: Array[StringName]) -> void:
	# IVSBGFinisher adds an orbits and a positions visual per group IVTableSystemBuilder
	# builds, which is every small_bodies_groups row not flagged 'skip'. The positions
	# visual takes a different shader for a Lagrange-point group.
	var has_group := false
	var has_point_group := false
	var has_lagrange_group := false
	for row in IVTableData.get_n_rows(&"small_bodies_groups"):
		if IVTableData.get_db_bool(&"small_bodies_groups", &"skip", row):
			continue
		has_group = true
		var lp_integer := IVTableData.get_db_int(&"small_bodies_groups", &"lp_integer", row)
		if lp_integer == -1:
			has_point_group = true
		elif lp_integer >= 4:
			has_lagrange_group = true
	if !has_group:
		return
	_add_shader_name(shader_names, &"farwarp_vertex_shader", false)
	if IVGlobal.program.has(&"FragmentIdentifier"): # absent under Compatibility
		_add_shader_name(shader_names, &"instance_id_shader", false)
	if has_point_group:
		_add_shader_name(shader_names, &"orbiting_positions_id_shader", false)
	if has_lagrange_group:
		_add_shader_name(shader_names, &"orbiting_positions_lp_id_shader", false)


func _add_packed_model_steps(step_names: Array[StringName], step_materials: Array[Array]
		) -> void:
	# A body's model is built lazily, on the camera's first visit, so its materials are read
	# off an instance of the scene IVAssetPreloader loaded. The instance shares them with the
	# one IVBodyVisual will build, so drawing them compiles exactly what that model binds.
	var asset_preloader: IVAssetPreloader = IVGlobal.program.get(&"AssetPreloader")
	if !asset_preloader:
		return
	var packed_models: Array[PackedScene] = []
	for table in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table):
			var body_name := IVTableData.get_db_entity_name(table, row)
			var packed_model := asset_preloader.get_body_packed_model(body_name)
			if !packed_model or packed_models.has(packed_model): # bodies can share a model
				continue
			packed_models.append(packed_model)
			var model := packed_model.instantiate()
			var materials: Array[Material] = []
			_collect_materials(model, materials)
			model.free()
			if materials:
				step_names.append(body_name)
				step_materials.append(materials)


func _collect_materials(node: Node, materials: Array[Material]) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance and mesh_instance.mesh:
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if material and !materials.has(material):
				materials.append(material)
	for child in node.get_children():
		_collect_materials(child, materials)


func _any_body_has_rings() -> bool:
	for table in IVCoreSettings.body_tables:
		if IVTableData.db_find(table, &"has_rings", true) != -1:
			return true
	return false


func _any_body_orbits() -> bool:
	# IVTableSystemBuilder reads parentage from the 'orbit' reference, and its absence marks
	# the tree root — the one body IVBodyFinisher gives no IVPathVisual.
	for table in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table):
			if IVTableData.get_db_int(table, &"orbit", row) != -1:
				return true
	return false


# Appends shader_name if it names a spatial Shader in IVGlobal.resources not already listed.
# A sky shader cannot go on a mesh and a canvas shader has no reason to. report_missing is
# for a project-supplied key, where a typo is the likely cause; a Core key that a
# stripped-down project has removed from the registry is not worth a warning.
func _add_shader_name(shader_names: Array[StringName], shader_name: StringName,
		report_missing: bool) -> void:
	if shader_names.has(shader_name):
		return
	var shader: Shader
	if IVGlobal.resources.get(shader_name) is Shader:
		shader = IVGlobal.resources[shader_name]
	if !shader:
		if report_missing:
			push_warning("IVShaderWarmup: '%s' is not a Shader in IVGlobal.resources"
					% shader_name)
		return
	if shader.get_mode() != Shader.MODE_SPATIAL:
		if report_missing:
			push_warning("IVShaderWarmup: skipping '%s'; only a spatial shader can be warmed"
					% shader_name)
		return
	shader_names.append(shader_name)


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


func _add_quad(camera: Camera3D, material: Material, layers: int) -> void:
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
	if is_instance_valid(_shadow_geometry_camera):
		IVDynamicLight.remove_local_shadow_geometry(_shadow_geometry_camera)
	_shadow_geometry_camera = null
	if is_instance_valid(_temporary_rig):
		_temporary_rig.queue_free()
	_temporary_rig = null
