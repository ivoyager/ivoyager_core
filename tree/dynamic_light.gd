# dynamic_light.gd
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
class_name IVDynamicLight
extends DirectionalLight3D

## Dynamic system to generate proper light and shadows over vast scale
## differences.
##
## This node self-adds IVDynamicLight children that (together with itself)
## light different size domains via [member Light3D.light_cull_mask]. Only the
## near/middle lights have shadow maps, serving the local (true-position)
## scene; their casters carry [constant IVGlobal.LOCAL_SHADOW_CASTER], their
## shadow reach is clamped to the farwarp boundary, and their energy scales by
## [member IVSunOcclusionManager.camera_sun_visible_fraction] (which is how
## craft-scale objects get eclipse and ring shadows). Astronomical-scale
## shadows are analytic in the receiving shaders instead of shadow maps; see
## [IVSunOcclusionManager].[br][br]
##
## The parent light points in the direction from source to the camera.
## All lights are attenuated for source distance: the nonphysical curve by
## default, or physical illuminance times the metered exposure while
## [member IVExposureManager.physical_active] (which is how lit surfaces
## carry the compensating camera without any shader term).[br][br]
##
## Under the Compatibility renderer this falls back to a single unshadowed light
## unless [member IVCoreSettings.apply_gl_compatibility_shadows] re-enables the
## shadowed multi-light path. That renderer has historically had defects that
## broke the multi-light setup:[br]
##  1. light_cull_mask and/or shadow_caster_mask not respected.[br]
##  2. Wrong lighting energy with multiple lights (godotengine/godot#90259).[br]
##  3. Color handling shifts once any light casts shadows (same issue).[br]
## Re-test these on a given target before relying on Compatibility shadows.[br][br]
##
## With [member IVCoreSettings.apply_empty_shadow_pass_skip], a shadowed light switches its
## map off while nothing within its reach would draw into it or read it - both halves, since
## a caster with no receiver in this light's size domain is a map nobody consumes. What can
## take part is registered rather than searched for: an [IVBodyVisual] declares itself
## whenever it holds [constant IVGlobal.LOCAL_SHADOW_CASTER], and a project's own geometry
## through [method add_local_shadow_geometry].[br]


## Rendered light energy of each star's top light, keyed by star body name — the number the
## engine multiplies a lit ALBEDO by. Published for the shaders that composite their own
## result and so have to apply that multiply themselves; [IVSunOcclusionManager] feeds it to
## them per body, beside the star's direction and angular radius.
static var star_light_energies: Dictionary[StringName, float] = {}
## False switches off the shadow map of every light that has one, overriding its table row
## and [member IVCoreSettings.apply_empty_shadow_pass_skip]; the lights still light their size
## domains. [IVGraphicsManager] sets this from the user's Shadow Resolution option, and frees
## the atlas along with it; setting it directly leaves an allocated atlas in place. Under the
## Compatibility renderer a change can stall on shader compiles, as that skip's flips can: the
## frame's shadowed-light count is a specialization input for every lit shader (see
## [code]GRAPHICS_PROFILING.md[/code]).
static var shadow_maps_enabled := true

## Reach multiple within which local geometry switches an idle shadow map back on.
const SHADOW_ENABLE_REACH_RATIO := 1.25
## Reach multiple beyond which a live shadow map may start counting down to off.
const SHADOW_DISABLE_REACH_RATIO := 2.0
## Frames the off condition must hold before a live shadow map switches off.
const SHADOW_DISABLE_DELAY_FRAMES := 120

# Everything that takes part in the local shadow maps, keyed together: the VisualInstance3D
# layers each node carries, and the extent its origin stands for. Maintained by grant
# changes rather than by a per-frame sweep, so reading it costs one short loop.
static var _local_shadow_layers: Dictionary[Node3D, int] = {}
static var _local_shadow_radii: Dictionary[Node3D, float] = {}

# from table
var energy_multiplier: float
var shadow_max_floor: float
var shadow_max_ceiling: float
var shadow_max_target_plus := NAN
var shadow_max_star_orbiter_plus := NAN
var apply_sun_occlusion := false


var _body_name: StringName
var _top_light: bool
var _row: int
var _shared: Array[float]
var _process_shadow_distances: bool
var _shadow_capable: bool
var _skip_empty_shadow_passes: bool
var _idle_shadow_frames := 0
var _add_shadow_target_dist: bool
var _add_shadow_star_orbiter_dist: bool

var _energy_at_1_au := IVCoreSettings.nonphysical_energy_at_1_au
var _attenuation_exponent := IVCoreSettings.nonphysical_attenuation_exponent
var _star_absolute_magnitude := NAN # lazy from the parent star body (top light only)

# top light only
var _camera: Camera3D
var _camera_star_orbiter: Node3D



## Declares project geometry that takes part in the local shadow maps, so that
## [member IVCoreSettings.apply_empty_shadow_pass_skip] can see it - a level scene, a
## lander in a crater, anything that is not an [IVBody]. An [IVBodyVisual] declares itself
## whenever it holds [constant IVGlobal.LOCAL_SHADOW_CASTER], so a project never calls this
## for a body.[br][br]
##
## [param visual_layers] is the [member VisualInstance3D.layers] value the geometry
## carries: its size-domain bit (see
## [method IVCoreSettings.get_visualinstance3d_layer_for_size]) plus
## [constant IVGlobal.LOCAL_SHADOW_CASTER] if it casts. Both matter - a light needs
## something to draw into its map [i]and[/i] something in its own cull mask to read it.
## Distance is measured to [param node3d]'s origin less [param extent_radius], so register
## the root of a local scene, or several nodes where one origin does not stand for the
## whole. A hidden node is ignored while it stays hidden. Removed automatically when the
## node leaves the tree; register again after re-adding.
static func add_local_shadow_geometry(node3d: Node3D, visual_layers: int,
		extent_radius := 0.0) -> void:
	assert(!_local_shadow_layers.has(node3d), "Already added: " + str(node3d))
	_local_shadow_layers[node3d] = visual_layers
	_local_shadow_radii[node3d] = extent_radius
	# A body re-enters this registry every time its caster grant returns, but the one-shot
	# connection only clears itself by firing, so re-connecting would be an error.
	var on_tree_exiting := remove_local_shadow_geometry.bind(node3d)
	if !node3d.tree_exiting.is_connected(on_tree_exiting):
		node3d.tree_exiting.connect(on_tree_exiting, CONNECT_ONE_SHOT)


## Removes geometry declared by [method add_local_shadow_geometry]. Safe to call for a
## node that was never added.
static func remove_local_shadow_geometry(node3d: Node3D) -> void:
	_local_shadow_layers.erase(node3d)
	_local_shadow_radii.erase(node3d)


## External call should provide [param body_name] only.
func _init(body_name: StringName, top_light := true, row := -1,
		shared: Array[float] = [0.0, 0.0, 0.0]) -> void:
	_body_name = body_name
	_top_light = top_light
	# The Compatibility renderer falls back to a single unshadowed light (the
	# gl_compatibility table row) unless apply_gl_compatibility_shadows re-enables
	# the shadowed multi-light path used by Forward+.
	var single_compat_light := (IVGlobal.is_gl_compatibility
			and not IVCoreSettings.apply_gl_compatibility_shadows)
	if top_light:
		row = _get_top_light(single_compat_light)
	_row = row
	_shared = shared
	IVTableData.db_build_object(self, &"dynamic_lights", row)
	# The table's intent, captured before _process starts writing shadow_enabled per frame.
	# Nothing else can recover it: db_build_object skips a false BOOL, so only the shadowed
	# rows ever set the property at all.
	_shadow_capable = shadow_enabled
	_process_shadow_distances = not single_compat_light
	_skip_empty_shadow_passes = _shadow_capable and IVCoreSettings.apply_empty_shadow_pass_skip
	# The skip reads the caster grant to decide whether anything is in reach, so a reach
	# past where IVBody.update_farwarp() stops granting would retire a live map.
	assert(!_skip_empty_shadow_passes
			or shadow_max_ceiling <= IVCoreSettings.local_shadow_caster_ceiling,
			"dynamic_lights row %s reaches past IVCoreSettings.local_shadow_caster_ceiling" % row)
	_add_shadow_target_dist = !is_nan(shadow_max_target_plus)
	_add_shadow_star_orbiter_dist = !is_nan(shadow_max_star_orbiter_plus)
	name = "DynamicLight" + str(row)


func _ready() -> void:
	if !_top_light:
		return
	# Only top light connects to camera or has children!
	IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	# The near/middle children carry the shadow maps; the single-light
	# Compatibility fallback (no shadow distances processed) adds none.
	if _process_shadow_distances:
		_add_child_lights()


func _process(_delta: float) -> void:
	const AU := IVUnits.AU
	
	# top light (only top can have _camera)
	if _camera:
		var camera_global_position := _camera.global_position
		var source_vector := camera_global_position - global_position
		var energy := NAN
		if IVExposureManager.physical_active:
			# Physical: metered exposure x illuminance x gain, over pi for the
			# Lambert convention (rendered diffuse = ALBEDO * energy * NdotL).
			var absolute_magnitude := _get_star_absolute_magnitude()
			if !is_nan(absolute_magnitude):
				var apparent_magnitude := IVPhotometry.get_apparent_magnitude(absolute_magnitude,
						source_vector.length())
				var illuminance := IVPhotometry.get_illuminance_from_apparent_magnitude(
						apparent_magnitude)
				energy = IVExposureManager.exposure * illuminance * IVExposureManager.gain / PI
		if is_nan(energy):
			var source_dist_au := source_vector.length() / AU
			energy = _energy_at_1_au / (source_dist_au ** _attenuation_exponent)
		# parent light sets for all
		if !source_vector.is_zero_approx(): # camera at the source; edge case observed once
			# The light's roll is arbitrary, but its up must not lie along it. Godot's
			# default, +y, lies in the ecliptic, which most views share with their star.
			var up := Vector3.BACK # ecliptic north
			if absf(source_vector.normalized().dot(Vector3.BACK)) > 0.99:
				up = Vector3.UP
			look_at(camera_global_position, up)
		_shared[0] = energy

		if _process_shadow_distances:
			var star_orbiter_dist := 0.0
			if _camera_star_orbiter:
				star_orbiter_dist = (_camera_star_orbiter.global_position - camera_global_position).length()
			# parent light sets for all
			_shared[1] = _camera.position.length() # target distance
			_shared[2] = star_orbiter_dist

	# all lights
	var total_energy := _shared[0] * energy_multiplier
	if apply_sun_occlusion:
		# Local-scene eclipse/ring shadowing: at craft scale the occlusion field
		# is uniform, so it applies as a light-energy factor rather than
		# per-fragment shading. One-frame lag (manager processes at 100).
		total_energy *= IVSunOcclusionManager.camera_sun_visible_fraction
	light_energy = total_energy
	if _top_light:
		star_light_energies[_body_name] = total_energy
	# Only a row that the table gave a shadow map has a reach to compute; the far light
	# processes shadow distances for its children's sake but has none of its own.
	if _shadow_capable:
		var shadow_max_dist := shadow_max_floor
		if _add_shadow_target_dist:
			shadow_max_dist = maxf(shadow_max_dist, shadow_max_target_plus + _shared[1])
		if _add_shadow_star_orbiter_dist:
			shadow_max_dist = maxf(shadow_max_dist, shadow_max_star_orbiter_plus + _shared[2])
		shadow_max_dist = minf(shadow_max_dist, shadow_max_ceiling)
		# No map shadow may cross the farwarp boundary: everything farwarp-remapped
		# renders at distance > farwarp_start, while every true-position receiver
		# is inside it. Without this clamp, near casters stamp oversized shadows on
		# warp-compressed bodies, and a warped body's own light-space imprint
		# false-shadows its camera-space self. Reads last frame's value (lights
		# process at 0, IVFarwarpManager at 100) - a one-frame lag on a smooth
		# quantity.
		var farwarp_start := IVFarwarpManager.farwarp_start
		if farwarp_start > 0.0:
			shadow_max_dist = minf(shadow_max_dist, farwarp_start)
		var enable_shadow := shadow_maps_enabled
		if enable_shadow and _skip_empty_shadow_passes:
			enable_shadow = _get_shadow_enabled(shadow_max_dist)
		if shadow_enabled != enable_shadow: # Light3D's setter is not change-gated
			shadow_enabled = enable_shadow
		if !enable_shadow:
			return
		directional_shadow_max_distance = shadow_max_dist


func _clear_procedural() -> void:
	# Only connected for top light. The local-shadow registry is NOT cleared here: a project
	# node may outlive the procedural tree, and tree_exiting is each entry's lifecycle.
	_camera = null
	_camera_star_orbiter = null
	star_light_energies.erase(_body_name)


# On is immediate and off is delayed: a missing shadow is a visible defect where an idle
# pass is only a cost. Every flip also changes the frame's shadowed-directional-light count,
# which is a shader specialization input for every lit instance in the scene (see
# GRAPHICS_PROFILING.md), so flips must be rare rather than merely correct.
func _get_shadow_enabled(shadow_max_dist: float) -> bool:
	var reach_ratio := SHADOW_DISABLE_REACH_RATIO if shadow_enabled else SHADOW_ENABLE_REACH_RATIO
	if _has_local_shadow_work(shadow_max_dist * reach_ratio):
		_idle_shadow_frames = 0
		return true
	if !shadow_enabled:
		return false
	_idle_shadow_frames += 1
	return _idle_shadow_frames < SHADOW_DISABLE_DELAY_FRAMES


# Both halves, because either alone is a map nothing uses: at an Earth close-up the planet
# holds the caster bit while this light's size domain (0.1-100 km) is empty, and at the ISS
# the reverse would keep the middle light alive for a station it does not light.
#
# Only casters are registered, which answers the receiver half too: every shadowed reach is
# clamped by both shadow_max_ceiling and farwarp_start, and the grant by
# local_shadow_caster_ceiling and the same farwarp_start, so reach <= grant range and
# anything a light can reach is already granted. The _init assert holds the first half of
# that; the residual is a receiver whose centre sits just past the grant while its surface
# is just inside reach, bounded by its own radius and so inside the outer fifth that
# directional_shadow_fade_start has already faded away.
func _has_local_shadow_work(range_distance: float) -> bool:
	var camera := get_viewport().get_camera_3d()
	if !camera:
		return true # nothing to measure from; a configured map is the safe answer
	var camera_global_position := camera.global_position
	var has_caster := false
	var has_receiver := false
	for node3d: Node3D in _local_shadow_layers:
		if !node3d.is_visible_in_tree():
			continue # hidden by distance cull or IVSleepManager; it draws nothing
		var extent_radius: float = _local_shadow_radii[node3d]
		var distance := (node3d.global_position - camera_global_position).length() - extent_radius
		if distance > range_distance:
			continue
		var visual_layers: int = _local_shadow_layers[node3d]
		has_caster = has_caster or bool(visual_layers & IVGlobal.LOCAL_SHADOW_CASTER)
		has_receiver = has_receiver or bool(visual_layers & light_cull_mask)
		if has_caster and has_receiver:
			return true
	return false


func _get_star_absolute_magnitude() -> float:
	# Lazy: the top light is a child of its star body, but the characteristic
	# isn't guaranteed until the body is finished.
	if is_nan(_star_absolute_magnitude):
		var star := get_parent() as IVBody
		if star:
			var magnitude_var: Variant = star.characteristics.get(&"absolute_magnitude")
			if typeof(magnitude_var) == TYPE_FLOAT:
				var magnitude: float = magnitude_var
				_star_absolute_magnitude = magnitude
	return _star_absolute_magnitude


func _on_camera_tree_changed(camera: Camera3D, _parent: Node3D, star_orbiter: Node3D, _star: Node3D
		) -> void:
	# Only connected for top light.
	_camera = camera
	_camera_star_orbiter = star_orbiter # really star orbiter


func _get_top_light(gl_compatibility: bool) -> int:
	for row in IVTableData.get_n_rows(&"dynamic_lights"):
		if gl_compatibility != IVTableData.get_db_bool(&"dynamic_lights", &"gl_compatibility", row):
			continue
		var bodies: Array[StringName] = IVTableData.get_db_array(&"dynamic_lights", &"bodies", row)
		if bodies.has(_body_name):
			return row
	assert(false, "Could not find top light in dynamic_lights.tsv for " + _body_name)
	return -1


func _add_child_lights() -> void:
	for row in IVTableData.get_n_rows(&"dynamic_lights"):
		if row == _row:
			continue
		if IVTableData.get_db_bool(&"dynamic_lights", &"gl_compatibility", row):
			continue
		var bodies: Array[StringName] = IVTableData.get_db_array(&"dynamic_lights", &"bodies", row)
		if bodies.has(_body_name):
			var child_light := IVDynamicLight.new(_body_name, false, row, _shared)
			add_child(child_light)
