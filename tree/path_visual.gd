# path_visual.gd
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
class_name IVPathVisual
extends MeshInstance3D

## Visual representation of an [IVBody]'s orbit, or its [IVTrajectory] (a
## patched-conic path) when present.
##
## [b]Orbit mode[/b] (no [IVTrajectory]): transforms a unit circle, parabola or
## rectangular-hyperbola mesh into the body's elliptic, parabolic or hyperbolic
## orbit. The three "unit" meshes are reused for all such orbits.[br][br]
##
## [b]Trajectory mode[/b] (the body has an [IVTrajectory]): for a transfer segment, builds a
## generated [code]LINE_STRIP[/code] mesh (one surface per segment) from the trajectory's
## precomputed [member IVTrajectory.path], expressed in the lowest-common-ancestor frame of
## the segment primaries; this node reparents itself to that ancestor
## ([method IVTrajectory.get_lca]) while the body reparents through the segment primaries.
## The mesh is built once and cached.[br][br]
##
## Any segment can instead be drawn as a parking/capture orbit (see
## [member IVTrajectory.visual_orbits], [member IVTrajectory.end_remove]); while the body
## is in such a segment this node renders in orbit mode in the body's own parent frame and
## omits that segment from the polyline.
## [method _on_orbit_changed] is the single switchboard that, on each segment change (via
## [signal IVBody.orbit_changed]), selects the mode, reparents, and sets the mesh.[br][br]
##
## If [IVFragmentIdentifier] is present, an "id" shader allows mouse-over
## identification of the line.


const FRAGMENT_BODY_ORBIT := IVFragmentIdentifier.FRAGMENT_BODY_ORBIT

var _body: IVBody
var _trajectory: IVTrajectory # null in orbit mode
var _color: Color
var _is_orbit_group_visible: bool
var _body_huds_visible: bool # too close / too far
var _body_visible: bool # tracks _body.visible
var _dirty_orbit := true
var _trajectory_mesh: ArrayMesh # built once, reused across trajectory<->orbit mode toggles

var _fragment_identifier: IVFragmentIdentifier = IVGlobal.program.get(&"FragmentIdentifier")
var _body_huds_state: IVBodyHUDsState = IVGlobal.program[&"BodyHUDsState"]
var _circle_mesh: ArrayMesh = IVGlobal.resources[&"circle_mesh"]
var _parabola_mesh: ArrayMesh = IVGlobal.resources[&"parabola_mesh"]
var _rectangular_hyperbola_mesh: ArrayMesh = IVGlobal.resources[&"rectangular_hyperbola_mesh"]


func _init(body: IVBody) -> void:
	_body = body
	name = "PathVisual_" + body.name


func _ready() -> void:
	_body.orbit_changed.connect(_on_orbit_changed)
	_body_huds_state.visibility_changed.connect(_on_global_huds_changed)
	_body_huds_state.color_changed.connect(_set_color)
	_body.huds_visibility_changed.connect(_on_body_huds_changed)
	_body.visibility_changed.connect(_on_body_visibility_changed)
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	if _fragment_identifier: # use self-identifying fragment shader
		var data := _body.get_fragment_data(FRAGMENT_BODY_ORBIT)
		var fragment_id := _fragment_identifier.get_new_id_as_vec3(data)
		var shader_material := ShaderMaterial.new()
		shader_material.shader = IVGlobal.resources[&"orbit_id_shader"]
		shader_material.set_shader_parameter(&"fragment_id", fragment_id)
		material_override = shader_material
	else:
		var standard_material := StandardMaterial3D.new()
		standard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material_override = standard_material
	_set_color()
	# Parenting and display mode (orbit vs trajectory) are resolved per segment in
	# _on_orbit_changed, the single switchboard; nothing to reparent eagerly here.
	_body_huds_visible = _body.huds_visible
	_body_visible = _body.visible
	_on_global_huds_changed()


func _on_orbit_changed(orbit: IVOrbit, _is_intrinsic := false, _precession_only := false) -> void:
	if !visible:
		_dirty_orbit = true
		return
	_dirty_orbit = false
	_trajectory = _body.get_trajectory() # may have become null via end_remove
	# A parking/capture segment (or a body with no trajectory) draws as a normal orbit in
	# the body's parent frame; a transfer segment draws as the polyline in the LCA frame.
	var as_orbit := _trajectory == null \
			or _trajectory.is_orbit_segment(_trajectory.orbits.find(orbit))
	if as_orbit:
		_reparent(_body.get_parent())
		_set_orbit_mesh(orbit)
		return
	_reparent(_trajectory.get_lca())
	if not _trajectory_mesh:
		_trajectory_mesh = _build_trajectory_mesh()
	mesh = _trajectory_mesh
	transform = Transform3D.IDENTITY


# Sets the unit conic mesh and transform for orbit-mode display (no trajectory, or a
# parking/capture segment). The three unit meshes are shared across all such orbits.
func _set_orbit_mesh(orbit: IVOrbit) -> void:
	var e := orbit.get_eccentricity()
	if e < 1.0:
		mesh = _circle_mesh
		transform = orbit.get_unit_circle_transform()
	elif e > 1.0:
		mesh = _rectangular_hyperbola_mesh
		transform = orbit.get_unit_rectangular_hyperbola_transform()
	else:
		mesh = _parabola_mesh
		transform = orbit.get_unit_parabola_transform()


# Moves this node under [param new_parent] (the body's current parent in orbit mode, or
# the trajectory's LCA in trajectory mode), matching IVBody.set_orbit_and_parent's idiom.
func _reparent(new_parent: Node) -> void:
	if not new_parent or get_parent() == new_parent:
		return
	get_parent().remove_child(self)
	new_parent.add_child(self)


# Builds and returns a LINE_STRIP mesh (one surface per transfer segment) from the
# trajectory's precomputed path, already in the LCA frame (the caller applies an identity
# transform). Per-segment surfaces avoid a stray line across patch-point discontinuities;
# parking/capture segments (is_orbit_segment) are omitted — they draw as normal orbits.
func _build_trajectory_mesh() -> ArrayMesh:
	var path := _trajectory.path
	var n_segments := _trajectory.orbits.size()
	var array_mesh := ArrayMesh.new()
	if path.is_empty() or n_segments == 0:
		return array_mesh
	@warning_ignore("integer_division") # path.size() is exactly n_segments * vertices/segment
	var chunk := path.size() / n_segments
	for i in n_segments:
		if _trajectory.is_orbit_segment(i):
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = path.slice(i * chunk, (i + 1) * chunk)
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	return array_mesh


func _on_global_huds_changed() -> void:
	_is_orbit_group_visible = _body_huds_state.is_orbit_visible(_body.flags)
	_set_visibility_state()


func _on_body_huds_changed(is_visible_: bool) -> void:
	_body_huds_visible = is_visible_
	_set_visibility_state()


func _on_body_visibility_changed() -> void:
	_body_visible = _body.visible
	_set_visibility_state()


func _set_visibility_state() -> void:
	visible = _is_orbit_group_visible and _body_huds_visible and _body_visible
	if visible and _dirty_orbit:
		_on_orbit_changed(_body.orbit)


func _set_color() -> void:
	var color := _body_huds_state.get_orbit_color(_body.flags)
	if _color == color:
		return
	_color = color
	if _fragment_identifier:
		var shader_material: ShaderMaterial = material_override
		shader_material.set_shader_parameter(&"color", color)
	else:
		var standard_material: StandardMaterial3D = material_override
		standard_material.albedo_color = color
