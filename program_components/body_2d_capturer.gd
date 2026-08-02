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
class_name IVBody2DCapturer
extends RefCounted

## Stages an [IVBodyVisual] in a caller-owned [SubViewport] and renders a transparent
## 2D icon [Image].
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
const SHELLS_KEY_DIR := Vector3(0.3, -0.3, -1.0) ## Frontal key for shells models (full-disc lit).

var _viewport: SubViewport
var _camera: Camera3D
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _model_holder: Node3D
var _visual: IVBodyVisual
var _camera_distance: float
var _ambient := 0.0


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
## [param model_holder] must start empty and must already be in the tree.
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
	# The key owns the specular highlight. A body with any metallic_specular (Earth's ocean
	# most visibly) prints one blob per directional light, and a second blob reads as a
	# second sun no matter where the fill sits.
	_fill_light.light_specular = 0.0
	_orient_light(_fill_light, FILL_DIR)


## Stages [param visual] — a throwaway from [method IVBody.make_body_visual] — and returns
## its origin-centered AABB (pass back to [method frame_camera]). Takes ownership: the
## previous staging is freed, and this one is freed by [method clear_visual] or the next
## call.
func stage_visual(visual: IVBodyVisual) -> AABB:
	clear_visual()
	_model_holder.add_child(visual)
	# The visual is a second copy of a body that is still live in the main scene. Until this
	# lands it animates against sim time, and a star's copy reaches back into the real body to
	# parent a far-point sprite there. Nothing may process between add_child() and here --
	# add_child() readies the whole subtree inline, and idle dispatch is a later point in the
	# main loop, so this is the last instant before the first frame it could run.
	visual.set_static_preview()
	_visual = visual
	var aabb := compute_scene_aabb(_model_holder)
	visual.position -= aabb.get_center() # put the centroid on the turntable pivot
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	longest = maxf(longest, 0.001)
	_camera_distance = longest * 2.0 + 1.0
	_camera.transform = Transform3D(Basis(), Vector3(0.0, 0.0, _camera_distance))
	_camera.near = maxf(longest * 0.01, 0.001)
	_camera.far = _camera_distance + longest * 2.0
	_apply_ambient()
	return AABB(-aabb.size * 0.5, aabb.size)


## Frees the staged visual, if any.
func clear_visual() -> void:
	if _visual:
		# Out of the tree first, not merely queued. A queued node stays a child for the rest of
		# the frame, so the next staging's AABB would merge the outgoing body into it and frame
		# the new one at the old one's scale -- New Horizons sized as if it were Jupiter.
		_model_holder.remove_child(_visual)
		_visual.queue_free()
		_visual = null


## Returns the staged visual's model, or [code]null[/code] if nothing is staged. Use it to
## tell a shells model from a packed scene, or to reach the shells.
func get_staged_model() -> Node3D:
	if !_visual:
		return null
	return _visual.get_model()


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


## Renders once and returns the zoom that makes the staged body fill the frame, given the
## pose currently applied at [param current_zoom]. Must be awaited.
##
## [method frame_camera] can only fit the model's bounding box, and a box tilted on the
## turntable circumscribes far more than the body inside it — a sphere's box is a cube, which
## costs about a third of the frame at the default pose. Measuring what actually rendered
## sidesteps the shape problem entirely and lands every body at the same size.
func solve_fit_zoom(current_zoom: float) -> float:
	var image := await _render_once()
	if !image or image.is_empty():
		return current_zoom
	var used := image.get_used_rect()
	var extent := maxi(used.size.x, used.size.y)
	if extent <= 0:
		return current_zoom
	return current_zoom * float(extent) * FRAME_MARGIN / float(image.get_width())


## Orients the key light from [code](azimuth, elevation)[/code] radians, carrying the fill
## light with it. The two are one rig: the fill holds its [constant KEY_DIR]-to-
## [constant FILL_DIR] offset from wherever the key points, so moving the key moves the whole
## lighting setup rather than sliding one source past a second one anchored in place.
func set_key_light(azimuth: float, elevation: float) -> void:
	var key_dir := azimuth_elevation_to_direction(azimuth, elevation)
	_orient_light(_key_light, key_dir)
	var rig_rotation := Quaternion(KEY_DIR.normalized(), key_dir)
	_orient_light(_fill_light, rig_rotation * FILL_DIR)


func set_key_light_enabled(enabled: bool) -> void:
	_key_light.visible = enabled


func set_fill_light_enabled(enabled: bool) -> void:
	_fill_light.visible = enabled


## Scales both lights' energy. Raise above 1.0 to brighten dark materials.
func set_brightness(value: float) -> void:
	_key_light.light_energy = value
	_fill_light.light_energy = value


## Sets how much the unlit hemisphere is lifted out of black, 0.0 for none. Body shaders
## disable engine ambient and take it as a uniform that only [IVSunOcclusionManager] feeds,
## and it feeds nothing outside the live scene — so a staged visual has none until this.
func set_ambient(value: float) -> void:
	_ambient = value
	_apply_ambient()


# A DirectionalLight3D emits along its local -Z; orient -Z along [param shine_dir].
func _orient_light(light: DirectionalLight3D, shine_dir: Vector3) -> void:
	var up := Vector3.UP
	if absf(shine_dir.normalized().dot(Vector3.UP)) > 0.99:
		up = Vector3.BACK
	light.look_at_from_position(Vector3.ZERO, shine_dir, up)


func _apply_ambient() -> void:
	if !_visual:
		return
	var ambient_light := Vector3.ONE * _ambient
	_apply_ambient_recursive(_visual, ambient_light)


# Set on every ShaderMaterial rather than only those known to declare "ambient_light": a
# shell picks its shader from table data (and swaps in a cubemap variant), so which ones
# take the uniform isn't knowable from here. An unknown uniform is a no-op by design.
func _apply_ambient_recursive(node: Node, ambient_light: Vector3) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance:
		var material := mesh_instance.get_surface_override_material(0) as ShaderMaterial
		if material:
			material.set_shader_parameter(&"ambient_light", ambient_light)
	for child in node.get_children():
		_apply_ambient_recursive(child, ambient_light)


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


# Two awaits, then read back: the viewport renders continuously (UPDATE_ALWAYS), so the
# first frame_post_draw can return within a frame whose draw is already behind us and hand
# back the previous contents. An empty first read is normal rather than an error, hence the
# retry in capture_image(). See IVScreenshotManager._render_once(), which needs the same pair.
func _render_once() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()
