# body_2d_capturer.gd
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
@tool
class_name IVBody2DCapturer
extends RefCounted

## Editor-only helper that stages a body's 3D model in a caller-owned
## [SubViewport] and renders a transparent 2D icon [Image].
##
## [IVBody2DCaptureDialog] owns the viewport / camera / light / turntable-pivot
## nodes and passes them via [method bind_nodes]; this class drives framing,
## lighting and capture so the live preview and the saved icon are the same
## render. The rig (orthographic camera fit to the model AABB, a white key plus
## dimmer fill [DirectionalLight3D], transparent background) mirrors the engine's
## own [code]make_mesh_previews[/code] / [code]make_scene_preview[/code].

const ICON_SIZE := 256
const SUPERSAMPLE := 4 ## Internal render is [constant ICON_SIZE] × this, downscaled on capture.
const FRAME_MARGIN := 1.06 ## Padding around the model AABB (existing icons aren't edge-tangent).
const KEY_DIR := Vector3(-2.0, -1.0, -1.0) ## Default key-light shine direction (engine rig).
const FILL_DIR := Vector3(1.0, -1.0, -2.0) ## Fill-light shine direction (engine rig).
const FILL_COLOR := Color(0.7, 0.7, 0.7) ## Fill-light color (engine rig).
const DEFAULT_YAW := -PI / 6 ## Canonical turntable yaw (model spun −30°).
const DEFAULT_PITCH := PI / 6 ## Canonical turntable pitch (model tipped +30°).
const DEFAULT_BRIGHTNESS := 1.0 ## Light-energy multiplier; raise for dark materials.
const SPHEROID_KEY_DIR := Vector3(0.3, -0.3, -1.0) ## Frontal key for spheroids (full-disc lit).

var _viewport: SubViewport
var _camera: Camera3D
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _model_holder: Node3D
var _model: Node3D
var _camera_distance: float


## Returns the [code]file_prefix[/code] for a model filename: the text before the
## first dot ([code]Voyager.glb[/code] → [code]Voyager[/code];
## [code]Deimos.1_1000.glb[/code] → [code]Deimos[/code]).
static func get_model_prefix(glb_filename: String) -> String:
	return glb_filename.get_slice(".", 0)


## Returns the combined AABB, in [param root]'s local space, of every
## [VisualInstance3D] at or under [param root]. [param root] must be inside the tree.
static func compute_scene_aabb(root: Node3D) -> AABB:
	var aabbs: Array[AABB] = []
	_collect_aabbs(root, root, aabbs)
	if aabbs.is_empty():
		return AABB()
	var combined := aabbs[0]
	for i in range(1, aabbs.size()):
		combined = combined.merge(aabbs[i])
	return combined


static func _collect_aabbs(node: Node3D, root: Node3D, aabbs: Array[AABB]) -> void:
	var visual := node as VisualInstance3D
	if visual:
		var to_root := root.global_transform.affine_inverse() * visual.global_transform
		aabbs.append(to_root * visual.get_aabb())
	for child in node.get_children():
		var child_node3d := child as Node3D
		if child_node3d:
			_collect_aabbs(child_node3d, root, aabbs)


## Converts a shine direction to [code](azimuth, elevation)[/code] in radians.
static func direction_to_azimuth_elevation(direction: Vector3) -> Vector2:
	var unit := direction.normalized()
	return Vector2(atan2(unit.z, unit.x), asin(clampf(unit.y, -1.0, 1.0)))


## Converts [code](azimuth, elevation)[/code] radians to a unit shine direction.
static func azimuth_elevation_to_direction(azimuth: float, elevation: float) -> Vector3:
	var horizontal := cos(elevation)
	return Vector3(horizontal * cos(azimuth), sin(elevation), horizontal * sin(azimuth))


## Binds the caller-owned scene nodes this capturer drives. Sets the camera to
## orthographic and the fill light to its fixed rig direction/color.
## [param model_holder] must start empty.
func bind_nodes(viewport: SubViewport, camera: Camera3D, key_light: DirectionalLight3D,
		fill_light: DirectionalLight3D, yaw_pivot: Node3D, pitch_pivot: Node3D,
		model_holder: Node3D) -> void:
	_viewport = viewport
	_camera = camera
	_key_light = key_light
	_fill_light = fill_light
	_yaw_pivot = yaw_pivot
	_pitch_pivot = pitch_pivot
	_model_holder = model_holder
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_fill_light.light_color = FILL_COLOR
	_orient_light(_fill_light, FILL_DIR)


## Instantiates the packed model at [param glb_path], orients it with the shared
## body convention ([method IVBodyVisual.get_packed_model_reference_basis]), and
## stages it. Returns its origin-centered AABB (pass back to [method frame_camera]);
## empty AABB on load failure.
func load_model(glb_path: String) -> AABB:
	var packed_scene: PackedScene = load(glb_path)
	if !packed_scene:
		return AABB()
	var model := packed_scene.instantiate() as Node3D
	model.basis = IVBodyVisual.get_packed_model_reference_basis(1.0)
	return _finish_load(model)


## Stages a generic spheroid: a unit sphere flattened to [param oblateness]
## (polar / equatorial; 1.0 = sphere) with [param albedo_map] (or
## [param emission_map] for a star) as its surface. Returns its origin-centered AABB.
func load_spheroid(albedo_map: Texture2D, emission_map: Texture2D, oblateness: float) -> AABB:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0 * clampf(oblateness, 0.05, 2.0)
	sphere.radial_segments = 64
	sphere.rings = 32
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = sphere
	var material := StandardMaterial3D.new()
	if emission_map:
		material.emission_enabled = true
		material.emission_texture = emission_map
		if not albedo_map: # a star: glow at full value, unaffected by the rig lights
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color.BLACK
	if albedo_map:
		material.albedo_texture = albedo_map
	mesh_instance.material_override = material
	return _finish_load(mesh_instance)


# Adds [param model] under the turntable pivot, centers it, sets camera clip/depth
# from its size, and returns its origin-centered AABB.
func _finish_load(model: Node3D) -> AABB:
	clear_model()
	_model_holder.add_child(model)
	_model = model
	var aabb := compute_scene_aabb(_model_holder)
	model.position -= aabb.get_center() # put the centroid on the turntable pivot
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	longest = maxf(longest, 0.001)
	_camera_distance = longest * 2.0 + 1.0
	_camera.transform = Transform3D(Basis(), Vector3(0.0, 0.0, _camera_distance))
	_camera.near = maxf(longest * 0.01, 0.001)
	_camera.far = _camera_distance + longest * 2.0
	return AABB(-aabb.size * 0.5, aabb.size)


## Frees the staged model, if any.
func clear_model() -> void:
	if _model:
		_model.queue_free()
		_model = null


## Sets the turntable rotation, orthographic zoom and pan, fitting the rotated
## [param centered_aabb]. [param zoom] > 1 zooms out, < 1 zooms in. [param pan]
## offsets the view in the camera plane, in fractions of the framed size (e.g.
## [code](0.5, 0)[/code] shifts the model half a frame to the right).
func frame_camera(centered_aabb: AABB, yaw: float, pitch: float, zoom: float, pan: Vector2) -> void:
	_yaw_pivot.rotation = Vector3(0.0, yaw, 0.0)
	_pitch_pivot.rotation = Vector3(pitch, 0.0, 0.0)
	var rot_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var rotated := Transform3D(rot_basis, Vector3.ZERO) * centered_aabb
	var fit := maxf(rotated.size.x, rotated.size.y)
	var ortho_size := maxf(fit, 0.001) * FRAME_MARGIN * zoom
	_camera.size = ortho_size
	_camera.position = Vector3(-pan.x * ortho_size, pan.y * ortho_size, _camera_distance)


## Orients the key light from [code](azimuth, elevation)[/code] radians.
func set_key_light(azimuth: float, elevation: float) -> void:
	_orient_light(_key_light, azimuth_elevation_to_direction(azimuth, elevation))


func set_key_light_enabled(enabled: bool) -> void:
	_key_light.visible = enabled


func set_fill_light_enabled(enabled: bool) -> void:
	_fill_light.visible = enabled


## Scales both lights' energy. Raise above 1.0 to brighten dark materials.
func set_brightness(value: float) -> void:
	_key_light.light_energy = value
	_fill_light.light_energy = value


# A DirectionalLight3D emits along its local -Z; orient -Z along [param shine_dir].
func _orient_light(light: DirectionalLight3D, shine_dir: Vector3) -> void:
	var up := Vector3.UP
	if absf(shine_dir.normalized().dot(Vector3.UP)) > 0.99:
		up = Vector3.BACK
	light.look_at_from_position(Vector3.ZERO, shine_dir, up)


## Renders the bound viewport and returns an RGBA8 icon at [constant ICON_SIZE].
## Must be awaited. Returns null on failure.
func capture_image() -> Image:
	var image := await _render_once()
	if !image or image.is_empty():
		image = await _render_once()
	if !image or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	image.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	return image


# Awaits real editor frames (the viewport renders continuously via UPDATE_ALWAYS),
# then reads the texture back. We must NOT call RenderingServer.force_draw() from a
# tool script: forcing a re-entrant draw inside the editor's own frame corrupts the
# shared RenderingServer, which then breaks thumbnail generation and crashes manual
# Reimport later in the session.
func _render_once() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()
