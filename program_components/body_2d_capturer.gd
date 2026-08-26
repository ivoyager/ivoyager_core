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
## render. The rig is a perspective camera at [constant VIEW_RADII] body radii, a white key
## plus dimmer fill [DirectionalLight3D], and a transparent background.[br][br]
##
## A staged visual is a copy of a body the simulator is still drawing, and the managers that
## feed a live body's shaders every frame never see it -- so anything they supply has to be
## supplied here or the copy renders against shader defaults. That is the ambient light, and
## the sun ([method set_key_light]): the key light IS the staged body's sun, or a body with a
## photometric law or an atmosphere is shaded for one sun and lit by another.

const ICON_SIZE := 256
const SUPERSAMPLE := 4 ## Internal render is [constant ICON_SIZE] × this, downscaled on capture.
const FRAME_MARGIN := 1.06 ## Padding around the model AABB (existing icons aren't edge-tangent).
const VIEW_RADII := 6.0 ## Camera distance in reference radii; twice the app's own VIEW_ZOOM.
## Alpha below this is not a silhouette. See [method get_silhouette_rect].
const SILHOUETTE_ALPHA := 8.0 / 255.0
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
var _bounding_radius := 1.0
var _ambient := 0.0
var _toward_sun := -KEY_DIR.normalized()


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
	# Perspective, not orthographic, and it is not a cosmetic choice. A shader takes VIEW from
	# the view-space POSITION, so an orthographic projection hands a disc-photometry law a mu
	# that reaches zero wherever the camera node happens to sit while the projection still
	# draws the sphere out to its full radius -- and it hands an atmosphere a ray from a point
	# the rasterizer is not looking from, which puts the whole limb ring in the wrong place.
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_fill_light.light_color = FILL_COLOR
	# The key owns the specular highlight. A body with any metallic_specular (Earth's ocean
	# most visibly) prints one blob per directional light, and a second blob reads as a
	# second sun no matter where the fill sits.
	_fill_light.light_specular = 0.0
	_orient_light(_fill_light, FILL_DIR)


## Stages [param visual] — a throwaway from [method IVBody.make_body_visual] — and returns
## its origin-centered AABB (pass back to [method frame_camera]). Takes ownership: the
## previous staging is freed, and this one is freed by [method clear_visual] or the next
## call.[br][br]
##
## [param reference_radius] is the body's own camera radius ([method IVBody.get_camera_radius]),
## which sets the camera distance and so how strong the perspective is; 0 falls back to the
## model's bounding radius, which is what a packed spacecraft wants -- its table radius is a
## placeholder against a model spanning tens of metres, and the same multiple of it would put
## the camera inside the model.
func stage_visual(visual: IVBodyVisual, reference_radius := 0.0) -> AABB:
	clear_visual()
	_model_holder.add_child(visual)
	# The visual is a second copy of a body that is still live in the main scene. Until this
	# lands it animates against sim time, and a star's copy reaches back into the real body to
	# parent a far-point sprite there. Nothing may process between add_child() and here --
	# add_child() readies the whole subtree inline, and idle dispatch is a later point in the
	# main loop, so this is the last instant before the first frame it could run.
	# A star's disc needs the preview camera's distance to scale itself to, so solve the
	# framing first. Both steps below are synchronous, which is what the note above requires.
	_visual = visual
	var aabb := compute_scene_aabb(_model_holder)
	# The sphere circumscribing the box, which is what the near/far planes and the distance
	# floor have to clear: the turntable spins the body under them, and no rotation reaches
	# past it.
	_bounding_radius = maxf(aabb.size.length() * 0.5, 0.001)
	if reference_radius <= 0.0:
		reference_radius = _bounding_radius
	_camera_distance = maxf(reference_radius * VIEW_RADII, _bounding_radius * 1.05)
	visual.set_static_preview(_camera_distance)
	visual.position -= aabb.get_center() # put the centroid on the turntable pivot
	_camera.transform = Transform3D(Basis(), Vector3(0.0, 0.0, _camera_distance))
	_camera.near = maxf((_camera_distance - _bounding_radius) * 0.5, 1e-5)
	_camera.far = _camera_distance + _bounding_radius * 2.0
	_apply_ambient()
	_apply_sun_direction()
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


## Sets the turntable rotation, zoom and pan, fitting the rotated [param centered_aabb].
## [param zoom] > 1 zooms out, < 1 zooms in. [param pan] offsets the view in the camera plane,
## in fractions of the framed size (e.g. [code](0.5, 0)[/code] shifts the model half a frame
## to the right).[br][br]
##
## The distance is fixed by [method stage_visual], so zoom narrows the field of view instead
## of moving the camera -- a crop, which leaves the perspective, and every shader that reads a
## view ray, untouched.
func frame_camera(centered_aabb: AABB, yaw: float, pitch: float, zoom: float, pan: Vector2) -> void:
	_yaw_pivot.rotation = Vector3(0.0, yaw, 0.0)
	_pitch_pivot.rotation = Vector3(pitch, 0.0, 0.0)
	var rot_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var rotated := Transform3D(rot_basis, Vector3.ZERO) * centered_aabb
	var fit := maxf(rotated.size.x, rotated.size.y)
	var half_frame := maxf(fit, 0.001) * FRAME_MARGIN * zoom * 0.5
	half_frame = minf(half_frame, _camera_distance * 0.999)
	var tangent := half_frame / sqrt(maxf(_camera_distance * _camera_distance
			- half_frame * half_frame, 1e-12))
	_camera.fov = rad_to_deg(2.0 * atan(tangent))
	var frame_height := 2.0 * _camera_distance * tangent
	_camera.position = Vector3(-pan.x * frame_height, pan.y * frame_height, _camera_distance)


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
	var used := get_silhouette_rect(image)
	var extent := maxi(used.size.x, used.size.y)
	if extent <= 0:
		return current_zoom
	return current_zoom * float(extent) * FRAME_MARGIN / float(image.get_width())


## Returns the rect enclosing [param image]'s texels at or above [constant SILHOUETTE_ALPHA].
##
## [method Image.get_used_rect] takes a single alpha step as visible, which an atmosphere
## defeats: its ring fades to nothing over a shell that can stand well clear of the body
## (Titan's is 1.415 mean radii), so a fit keyed to nonzero alpha sizes each body by how far
## its own invisible air reaches -- 7 % of Titan's diameter, measured -- and bodies that
## should read as one family come out at different sizes.
static func get_silhouette_rect(image: Image) -> Rect2i:
	var rgba := image
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba = Image.new()
		rgba.copy_from(image)
		rgba.convert(Image.FORMAT_RGBA8)
	var data := rgba.get_data()
	var width := rgba.get_width()
	var height := rgba.get_height()
	var threshold := int(SILHOUETTE_ALPHA * 255.0)
	var min_x := width
	var max_x := -1
	var min_y := 0
	var max_y := -1
	var index := 3
	for y in height:
		var row_min := -1
		var row_max := -1
		for x in width:
			if data[index] >= threshold:
				if row_min == -1:
					row_min = x
				row_max = x
			index += 4
		if row_max == -1:
			continue
		min_x = mini(min_x, row_min)
		max_x = maxi(max_x, row_max)
		if max_y == -1:
			min_y = y
		max_y = y
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Orients the key light from [code](azimuth, elevation)[/code] radians, carrying the fill
## light with it. The two are one rig: the fill holds its [constant KEY_DIR]-to-
## [constant FILL_DIR] offset from wherever the key points, so moving the key moves the whole
## lighting setup rather than sliding one source past a second one anchored in place.
##
## The key is also the staged body's SUN: it is pushed to every shader material as
## [code]sun_direction[/code], which is what a disc-photometry law, an atmosphere and the
## occlusion terms all take their geometry from. Call again after staging a new visual.
func set_key_light(azimuth: float, elevation: float) -> void:
	var key_dir := azimuth_elevation_to_direction(azimuth, elevation)
	_orient_light(_key_light, key_dir)
	var rig_rotation := Quaternion(KEY_DIR.normalized(), key_dir)
	_orient_light(_fill_light, rig_rotation * FILL_DIR)
	_toward_sun = -key_dir.normalized()
	_apply_sun_direction()


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
	_apply_shader_parameter(_visual, &"ambient_light", ambient_light)


# IVSunOcclusionManager feeds sun_direction to the LIVE bodies' materials every frame and
# never sees a staged copy, so without this the whole photometric chain -- lunar_lambert,
# minnaert_k, atm_sun_transmittance, the atmosphere limb's entire ray geometry -- runs
# against the shader default while the DirectionalLight3D lights the body from somewhere
# else. sun_angular_radius stays 0: a directional light casts a geometrically sharp
# terminator, and a softened twilight would not be the one the lit surface beside it has.
func _apply_sun_direction() -> void:
	if !_visual:
		return
	_apply_shader_parameter(_visual, &"sun_direction", _toward_sun)
	_apply_shader_parameter(_visual, &"sun_angular_radius", 0.0)


# Set on every ShaderMaterial rather than only those known to declare the uniform: a shell
# picks its shader from table data (and swaps in a cubemap variant), so which ones take
# which uniform isn't knowable from here. An unknown uniform is a no-op by design.
func _apply_shader_parameter(node: Node, parameter: StringName, value: Variant) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance:
		var material := mesh_instance.get_surface_override_material(0) as ShaderMaterial
		if material:
			material.set_shader_parameter(parameter, value)
	for child in node.get_children():
		_apply_shader_parameter(child, parameter, value)


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
	# Resize FIRST: a transparent-background viewport hands back premultiplied colour (see
	# unpremultiply_alpha), and premultiplied is the only form a filter may average.
	image.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	unpremultiply_alpha(image)
	return image


## Converts an image read back from a transparent-background [SubViewport] to the straight
## (non-premultiplied) alpha a PNG means, in place.
##
## Nothing in the rig asks for premultiplied output and everything produces it: a partly
## covered edge texel is the resolve of covered samples against nothing, and an atmosphere
## limb draws with [code]blend_premul_alpha[/code] outright. Saved unconverted, every
## partly transparent texel composites at [code]alpha[/code] times its true colour — which
## on a 1 px silhouette edge is a dark fringe nobody sees, and over an atmosphere's ring is
## the whole ring, printed as a dark halo instead of glow.
##
## Where the ring is bright and thin the straight colour exceeds white, because an
## atmosphere ADDS light without occluding much and no straight-alpha encoding can say
## that. Alpha is raised to the brightest channel there rather than the colour clipped, so
## the composite over BLACK — what an icon is drawn on, and what the app itself shows —
## stays exact, and the cost is that a bright ring occludes a light background slightly
## more than the air really does.
static func unpremultiply_alpha(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var texel := image.get_pixel(x, y)
			if texel.a <= 0.0:
				continue
			var scale := maxf(texel.a, maxf(texel.r, maxf(texel.g, texel.b)))
			if scale <= 0.0:
				continue
			image.set_pixel(x, y, Color(texel.r / scale, texel.g / scale, texel.b / scale,
					scale))


# Two awaits, then read back: the viewport renders continuously (UPDATE_ALWAYS), so the
# first frame_post_draw can return within a frame whose draw is already behind us and hand
# back the previous contents. An empty first read is normal rather than an error, hence the
# retry in capture_image(). See IVScreenshotManager._render_once(), which needs the same pair.
func _render_once() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()
