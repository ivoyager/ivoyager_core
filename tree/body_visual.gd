# body_visual.gd
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
class_name IVBodyVisual
extends Node3D

## Provides a model reference frame and instantiates a body's model.
##
## This node is oriented and rotated by [IVBody], but is not itself scaled. It
## scales the model that it instantiates.[br][br]
##
## This node is not persisted. If "lazy init" is applicable, it is created by
## [IVBody] only if/when needed and remains through the current user session.
## (Lazy init is applicable if [IVLazyModelInitializer] is present and [IVBody]
## has [enum IVBody.BodyFlags].BODYFLAGS_LAZY_MODEL.)[br][br]
##
## Children can be added that share the model's axial tilt and rotation.
## In base Solar System setup, [IVBodyFinisher] adds [IVRings] for Saturn.[br][br]
##
## Note: It's not planned to implement collisions in ivoyager_core. It would be
## challenging (to say the least) to feed model shape interactions back to our
## own orbit physics.


## Body-frame reference basis used for orienting the model and rings.
var reference_basis: Basis
## Optional Script used in place of [IVShellsModel] when no PackedScene model
## is present. Must extend [IVShellsModel] and share its
## [code]_init(body_name, mean_radius, model_basis, shell, mesh_override)[/code] signature.
var replacement_shells_model_class: Script


var _body_name: StringName
var _m_radius: float
var _triaxial_size: Vector3
var _model: Node3D
var _local_shadow_caster := false



## Returns the body-frame reference [Basis] for a packed-scene model: uniformly
## scaled by [param model_scale] and rotated so the model's z-up axis becomes
## y-up.
static func get_packed_model_reference_basis(model_scale: float) -> Basis:
	const RIGHT_ANGLE := PI / 2
	return Basis().scaled(model_scale * Vector3.ONE).rotated(Vector3(1.0, 0.0, 0.0), RIGHT_ANGLE)


## [param triaxial_size] is the body's semi-axes in the IAU order (a at longitude 0,
## b at 90°E, c polar); an oblate body passes (equatorial, equatorial, polar). Resolved
## by [method IVBody.make_body_visual], which also applies any surface-class fallback.
func _init(body_name: StringName, mean_radius: float, triaxial_size: Vector3) -> void:
	_body_name = body_name
	_m_radius = mean_radius
	_triaxial_size = triaxial_size
	_local_shadow_caster = IVCoreSettings.get_static_local_shadow_caster(mean_radius)
	name = &"BodyVisual"
	# A PackedScene model (self-defining) always wins; otherwise the body is a shells model,
	# whose whole spec the preloader has already resolved (body rows + surface class).
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	var packed_model := asset_preloader.get_body_packed_model(_body_name)
	if packed_model:
		_build_packed_model(asset_preloader, packed_model)
		return
	_build_shells_model(asset_preloader)


func _ready() -> void:
	add_child(_model)


func is_local_shadow_caster() -> bool:
	return _local_shadow_caster


## Returns this visual's model: an [IVShellsModel] (the surface, and parent of any overlay
## shells) or an instantiated packed scene, depending on what the body's assets defined.
func get_model() -> Node3D:
	return _model


## Detaches this whole visual from the live simulation so it can be staged elsewhere as a
## still image, applying [method IVShellsModel.set_static_preview] to every shell it holds.
## Call right after adding a visual from [method IVBody.make_body_visual] to the tree, before
## it can process a frame. One way: there is no restoring the live behavior afterward.[br][br]
##
## [param camera_distance] is the preview camera's distance to the body, which a star's disc
## needs to scale itself to; pass it again through [method set_preview_camera_distance] if that
## camera is later moved or replaced.
func set_static_preview(camera_distance: float) -> void:
	_set_static_preview_recursive(self, camera_distance)


## Rescales a static preview's star disc to a preview camera that has been placed or moved
## since staging, applying [method IVShellsModel.set_preview_camera_distance] to every shell.
func set_preview_camera_distance(camera_distance: float) -> void:
	_set_preview_camera_distance_recursive(self, camera_distance)


func _set_static_preview_recursive(node3d: Node3D, camera_distance: float) -> void:
	var shells_model := node3d as IVShellsModel
	if shells_model:
		shells_model.set_static_preview(camera_distance)
	for child in node3d.get_children():
		var child_node3d := child as Node3D
		if child_node3d:
			_set_static_preview_recursive(child_node3d, camera_distance)


func _set_preview_camera_distance_recursive(node3d: Node3D, camera_distance: float) -> void:
	var shells_model := node3d as IVShellsModel
	if shells_model:
		shells_model.set_preview_camera_distance(camera_distance)
	for child in node3d.get_children():
		var child_node3d := child as Node3D
		if child_node3d:
			_set_preview_camera_distance_recursive(child_node3d, camera_distance)


## Grants/clears [constant IVGlobal.LOCAL_SHADOW_CASTER] on this visual's whole
## tree (see the constant's doc for the granting rules). Called per frame by
## [method IVBody.update_farwarp]; the recursion runs on state change only.
func set_local_shadow_caster(on: bool) -> void:
	if _local_shadow_caster == on:
		return
	_local_shadow_caster = on
	_set_local_shadow_caster_recursive(self, on)


func _set_local_shadow_caster_recursive(node3d: Node3D, on: bool) -> void:
	var visualinstance3d := node3d as VisualInstance3D
	if visualinstance3d:
		if on:
			visualinstance3d.layers |= IVGlobal.LOCAL_SHADOW_CASTER
		else:
			visualinstance3d.layers &= ~IVGlobal.LOCAL_SHADOW_CASTER
	for child in node3d.get_children():
		var child_node3d := child as Node3D
		if child_node3d:
			_set_local_shadow_caster_recursive(child_node3d, on)


func _build_packed_model(asset_preloader: IVAssetPreloader, packed_model: PackedScene) -> void:
	var model_scale := asset_preloader.get_body_model_scale(_body_name)
	reference_basis = get_packed_model_reference_basis(model_scale)
	_model = packed_model.instantiate()
	_model.basis = reference_basis
	_set_visibility_ranges()
	_set_layers()


func _build_shells_model(asset_preloader: IVAssetPreloader) -> void:
	const RIGHT_ANGLE := PI / 2
	# One basis serves both surface paths; only the scale term differs. A mesh (the body's
	# own, or its surface class's generic one) replaces the shared sphere and takes a
	# uniform scale, the mesh itself carrying the real figure (oblateness, ridge, DEM); the
	# shared sphere takes the figure as a triaxial scale. A body mesh is authored as the
	# displaced SphereMesh — same frame, same UV unwrap — so the same maps register on
	# either path and a body can gain or lose a custom mesh without touching them.
	var mesh := asset_preloader.get_body_mesh(_body_name)
	if mesh:
		reference_basis = Basis().scaled(
				asset_preloader.get_body_mesh_scale(_body_name) * Vector3.ONE)
	else:
		# The polar radius is the body's own (ultimately the table's, as the analytic
		# shadows use), not one solved back out of mean and equatorial: mean_radius is the
		# published volumetric mean, so inverting it as an arithmetic mean flattens Saturn
		# by an extra 200 km. The shared sphere carries longitude 0 on model +Z and 90°E
		# on +X, so (a, b, c) permutes here — the only place the IAU order does not
		# survive. Scaling precedes the rotations, so the a-axis stays locked to the
		# texture's longitude 0.
		reference_basis = Basis().scaled(Vector3(_triaxial_size.y, _triaxial_size.z,
				_triaxial_size.x))
	reference_basis = reference_basis.rotated(Vector3(0.0, 1.0, 0.0), -RIGHT_ANGLE)
	reference_basis = reference_basis.rotated(Vector3(1.0, 0.0, 0.0), RIGHT_ANGLE) # z-up!
	# The model self-builds its surface, child shells, visibility ranges and layers.
	if mesh:
		_model = IVShellsModel.new(_body_name, _m_radius, reference_basis, 0, mesh)
	elif replacement_shells_model_class:
		@warning_ignore("unsafe_method_access")
		_model = replacement_shells_model_class.new(_body_name, _m_radius, reference_basis)
	else:
		_model = IVShellsModel.new(_body_name, _m_radius, reference_basis)


# Packed-scene models are foreign node trees, so [IVBodyVisual] still recurses
# to set their visibility ranges and layers. Shells models self-configure (see
# [IVShellsModel]).
func _set_visibility_ranges() -> void:
	# A body with an [IVBodyPSF] manages its own visibility (the pixel-radius fade to its
	# PSF quad), so skip the fixed distance cull, matching the shells-model self-config path.
	var body: IVBody = IVBody.bodies.get(_body_name)
	if IVBodyPSF.is_applicable(body):
		return # the disc self-culls at its handoff; default 0.0 is no distance cull
	var visibility_range_end := _m_radius * IVCoreSettings.radius_multiplier_visibility_range_end
	_set_visibility_ranges_recursive(_model, visibility_range_end)


func _set_visibility_ranges_recursive(node3d: Node3D, visibility_range_end: float) -> void:
	var geometry := node3d as GeometryInstance3D
	# A packed scene may author its own cull distance; 0.0 is the engine's "unset" and so the
	# only case we have anything to say about.
	if geometry and geometry.visibility_range_end == 0.0:
		geometry.visibility_range_end = visibility_range_end
	for child in node3d.get_children():
		var child_node3d := child as Node3D
		if child_node3d:
			_set_visibility_ranges_recursive(child_node3d, visibility_range_end)


func _set_layers() -> void:
	var layers := IVCoreSettings.get_visualinstance3d_layer_for_size(_m_radius)
	if _local_shadow_caster:
		layers |= IVGlobal.LOCAL_SHADOW_CASTER
	_set_layers_recursive(_model, layers)


func _set_layers_recursive(node3d: Node3D, layers: int) -> void:
	var visualinstance3d := node3d as VisualInstance3D
	if visualinstance3d:
		visualinstance3d.layers = layers
	for child in node3d.get_children():
		var child_node3d := child as Node3D
		if child_node3d:
			_set_layers_recursive(child_node3d, layers)
