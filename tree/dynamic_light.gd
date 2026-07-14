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
## All lights are attenuated for source distance.[br][br]
##
## Under the Compatibility renderer this falls back to a single unshadowed light
## unless [member IVCoreSettings.apply_gl_compatibility_shadows] re-enables the
## shadowed multi-light path. That renderer has historically had defects that
## broke the multi-light setup:[br]
##  1. light_cull_mask and/or shadow_caster_mask not respected.[br]
##  2. Wrong lighting energy with multiple lights (godotengine/godot#90259).[br]
##  3. Color handling shifts once any light casts shadows (same issue).[br]
## Re-test these on a given target before relying on Compatibility shadows.[br]


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
var _add_shadow_target_dist: bool
var _add_shadow_star_orbiter_dist: bool

var _energy_at_1_au := IVCoreSettings.nonphysical_energy_at_1_au
var _attenuation_exponent := IVCoreSettings.nonphysical_attenuation_exponent

# top light only
var _camera: Camera3D
var _camera_star_orbiter: Node3D



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
	_process_shadow_distances = not single_compat_light
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
		var source_dist_au := source_vector.length() / AU
		var energy := _energy_at_1_au / (source_dist_au ** _attenuation_exponent)
		# parent light sets for all
		if !position.is_equal_approx(source_vector): # edge case observed once
			look_at(source_vector)
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
	if _process_shadow_distances:
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
		directional_shadow_max_distance = shadow_max_dist


func _clear_procedural() -> void:
	# Only connected for top light.
	_camera = null
	_camera_star_orbiter = null


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
