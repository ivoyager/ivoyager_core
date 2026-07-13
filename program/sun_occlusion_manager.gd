# sun_occlusion_manager.gd
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
class_name IVSunOcclusionManager
extends Node

## Drives the analytic sun-occlusion system (see
## [code]shaders/_sun_occlusion.gdshaderinc[/code]): feeds per-frame occluder
## and ring-shadow uniforms to every receiving material, and publishes a
## camera-point sun-visible fraction for local light dimming.
##
## Receivers are [IVBody] instances whose visuals carry a [ShaderMaterial]
## declaring the occlusion uniform interface (detected by the presence of
## [code]occluder_data_a[/code], so shaders opt in by declaring the uniforms).
## Materials are discovered lazily from [member IVBody.body_visual] and
## re-discovered whenever that instance changes (lazy models build late and can
## be swapped). Occluder candidates for a receiver are its parent, its parent's
## other satellites, and its own satellites (stars and sub-km bodies excluded);
## the [constant MAX_OCCLUDERS] whose shadow lands nearest the receiver's disc
## center are kept (ranked by how far the penumbra reaches past the limb).
## Ring-shadow uniforms feed every receiver in a ringed body's planetary
## system, so moons get ring shadows too.
##
## Processes at priority +100 so global positions are read after [IVCamera]
## (0) has moved and origin-shifted the Universe (see [IVFarwarpManager]).
## CPU mirrors of the shader math live in [IVAstronomy].[br][br]
##
## Receivers disable engine ambient and rebuild it from the manager-fed
## [code]ambient_light[/code] uniform, so shadows can never darken starlight
## (see the shaderinc header). The value comes from the [WorldEnvironment]
## ([code]AMBIENT_SOURCE_COLOR[/code] only; other sources feed zero). This feed
## continues when [member IVCoreSettings.apply_analytic_shadows] is false -
## that setting disables only the shadow terms and the light dimming.

const MAX_OCCLUDERS := 6 # must match the uniform array size in _sun_occlusion.gdshaderinc
const MIN_OCCLUDER_RADIUS := 1.0 * IVUnits.KM # excludes spacecraft-scale "occluders"

## Fraction of the sun's disc visible from the camera's position, from the same
## occluder set plus ring transmission; 1.0 when unobstructed or no camera.
## Local (near/middle) light energy scales by this, which is how craft and
## other shadow-map-scale objects get eclipse and ring shadows: at their scale
## the occlusion field is uniform, and their culled visibility ranges guarantee
## nothing camera-remote is on screen to be wrongly dimmed. Read-only.
static var camera_sun_visible_fraction := 1.0

var _analytic_enabled: bool = IVCoreSettings.apply_analytic_shadows

var _camera: Camera3D
var _camera_star_orbiter: IVBody
var _world_environment: WorldEnvironment # persistent scene node; found lazily
var _ambient_light := Vector3.ZERO # scene ambient color x energy, for the shadow uniforms

# Receiver material caches, keyed by body name; rebuilt when the cached
# body_visual instance changes. A shader opts in by declaring the occlusion
# uniforms (checked once per Shader).
var _registered_visuals: Dictionary[StringName, Node3D] = {}
var _registered_materials: Dictionary[StringName, Array] = {} # Array[ShaderMaterial]
var _shader_opt_ins: Dictionary[Shader, bool] = {}
var _candidate_lists: Dictionary[StringName, Array] = {} # Array[IVBody]

# A ringed body's own rings material, keyed by that body's name. Kept apart from
# the body's surface materials because it takes a different occluder set: the
# ringed body shadows its own rings, whereas a surface excludes itself.
var _ring_materials: Dictionary[StringName, ShaderMaterial] = {}

# Ring-shadow sources, keyed by the ringed body's name (= its system key).
var _rings_nodes: Dictionary[StringName, IVRings] = {}
var _ring_profile_textures: Dictionary[StringName, Texture2D] = {}
var _ring_profile_images: Dictionary[StringName, Image] = {}

# Per-frame scratch that _select_occluders fills. Each receiver is fed a
# duplicate (see _feed_body): set_shader_parameter aliases the passed array
# rather than copying it, so feeding this shared scratch directly let a later
# receiver's fill leak back into materials already fed - every surface ended up
# reading the same end-of-frame array (a transiting occluder at slot 0 vanished
# while the frankensteined slot 1 rendered someone else's).
var _occluder_data_a := PackedVector4Array()
var _occluder_data_b := PackedVector4Array()
var _keeper_bodies: Array[IVBody] = []
var _keeper_scores := PackedFloat64Array()



func _ready() -> void:
	# With apply_analytic_shadows off, this keeps running for the ambient_light
	# feed alone: opted-in shaders disable engine ambient and rebuild it from
	# that uniform, so it must flow regardless (the shadow terms stay inert and
	# camera_sun_visible_fraction stays 1.0).
	process_priority = 100 # after IVCamera (0) has origin-shifted the Universe
	_occluder_data_a.resize(MAX_OCCLUDERS)
	_occluder_data_b.resize(MAX_OCCLUDERS)
	IVGlobal.current_camera_changed.connect(_on_current_camera_changed)
	IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)


func _process(_delta: float) -> void:
	_update_ambient_light()
	if _analytic_enabled:
		_update_camera_fraction()
	for body_name: StringName in IVBody.bodies:
		var body := IVBody.bodies[body_name]
		if not body.visible or body.flags & IVBody.BodyFlags.BODYFLAGS_STAR:
			continue
		var body_visual := body.body_visual
		if not body_visual:
			continue
		if _registered_visuals.get(body_name) != body_visual:
			_discover_visual(body_name, body_visual)
		var materials: Array = _registered_materials[body_name]
		if materials.is_empty():
			continue
		_feed_body(body, materials)


# Shadowed regions must keep receiving ambient (the shaders restore the exact
# ambient deficit as emission; see _sun_occlusion.gdshaderinc), so the shadow
# uniforms carry the scene ambient. Only AMBIENT_SOURCE_COLOR is readable as a
# value; other sources feed zero and shadows there go to black.
func _update_ambient_light() -> void:
	if not is_instance_valid(_world_environment):
		_world_environment = null
		for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			_world_environment = node as WorldEnvironment
			break
	_ambient_light = Vector3.ZERO
	if not _world_environment:
		return
	var environment := _world_environment.environment
	if environment and environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR:
		var color := environment.ambient_light_color
		_ambient_light = Vector3(color.r, color.g, color.b) * environment.ambient_light_energy


func _on_current_camera_changed(camera: Camera3D) -> void:
	_camera = camera


func _on_camera_tree_changed(_camera_node: Camera3D, _parent: Node3D, star_orbiter: Node3D,
		_star: Node3D) -> void:
	_camera_star_orbiter = star_orbiter as IVBody


func _clear_procedural() -> void:
	_camera = null
	_camera_star_orbiter = null
	_registered_visuals.clear()
	_registered_materials.clear()
	_ring_materials.clear()
	_candidate_lists.clear()
	_rings_nodes.clear()
	_ring_profile_textures.clear()
	_ring_profile_images.clear()
	camera_sun_visible_fraction = 1.0


# Walks a (re)built body_visual for opted-in ShaderMaterials: surface/shell
# materials into the returned list, the rings material into _ring_materials
# (fed separately), and registers any IVRings node as its system's ring-shadow
# source.
func _discover_visual(body_name: StringName, body_visual: Node3D) -> void:
	_ring_materials.erase(body_name)
	var materials: Array[ShaderMaterial] = []
	_discover_recursive(body_visual, body_name, materials)
	_registered_visuals[body_name] = body_visual
	_registered_materials[body_name] = materials


func _discover_recursive(node: Node, body_name: StringName, materials: Array[ShaderMaterial]
		) -> void:
	var rings := node as IVRings
	if rings:
		_register_rings(body_name, rings)
		var ring_material := rings.get_surface_override_material(0) as ShaderMaterial
		if ring_material and _shader_opts_in(ring_material.shader):
			if IVGlobal.is_gl_compatibility:
				ring_material.set_shader_parameter(&"compat_albedo_shadow", true)
			_ring_materials[body_name] = ring_material
		return # rings take a distinct occluder set; not a surface receiver
	var mesh_instance := node as MeshInstance3D
	if mesh_instance:
		var material := mesh_instance.get_surface_override_material(0) as ShaderMaterial
		if material and _shader_opts_in(material.shader):
			if IVGlobal.is_gl_compatibility:
				material.set_shader_parameter(&"compat_albedo_shadow", true)
			materials.append(material)
	for child in node.get_children():
		_discover_recursive(child, body_name, materials)


func _shader_opts_in(shader: Shader) -> bool:
	if not shader:
		return false
	if _shader_opt_ins.has(shader):
		return _shader_opt_ins[shader]
	var opts_in := false
	for uniform: Dictionary in shader.get_shader_uniform_list():
		if uniform[&"name"] == "occluder_data_a":
			opts_in = true
			break
	_shader_opt_ins[shader] = opts_in
	return opts_in


func _register_rings(system_name: StringName, rings: IVRings) -> void:
	if _rings_nodes.get(system_name) == rings:
		return
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	_rings_nodes[system_name] = rings
	_ring_profile_textures[system_name] = asset_preloader.get_rings_shadow_profile_texture(
			rings.name)
	_ring_profile_images[system_name] = asset_preloader.get_rings_shadow_profile_image(
			rings.name)


func _feed_body(body: IVBody, materials: Array) -> void:
	var star := body.star
	if not star or star == body:
		return
	var body_position := body.global_position
	var star_vector := star.global_position - body_position
	var star_distance := star_vector.length()
	if star_distance <= 0.0:
		return
	var sun_direction := star_vector / star_distance
	var sun_angular_radius := star.mean_radius / star_distance
	var occluder_count := 0
	var occluder_data_a := PackedVector4Array()
	var occluder_data_b := PackedVector4Array()
	if _analytic_enabled:
		occluder_count = _select_occluders(body, body_position, sun_direction,
				sun_angular_radius)
		if occluder_count > 0:
			# Own copy per receiver; the shared scratch aliases into fed materials.
			occluder_data_a = _occluder_data_a.duplicate()
			occluder_data_b = _occluder_data_b.duplicate()
	var system_name := StringName()
	if body.star_orbiter:
		system_name = body.star_orbiter.name
	var rings: IVRings = null
	if _analytic_enabled:
		rings = _rings_nodes.get(system_name)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter(&"sun_direction", sun_direction)
		material.set_shader_parameter(&"sun_angular_radius", sun_angular_radius)
		material.set_shader_parameter(&"ambient_light", _ambient_light)
		material.set_shader_parameter(&"occluder_count", occluder_count)
		if occluder_count > 0:
			material.set_shader_parameter(&"occluder_data_a", occluder_data_a)
			material.set_shader_parameter(&"occluder_data_b", occluder_data_b)
		if rings:
			material.set_shader_parameter(&"ring_alpha_r8", _ring_profile_textures[system_name])
			material.set_shader_parameter(&"ring_alpha_width",
					float(_ring_profile_textures[system_name].get_width()))
			material.set_shader_parameter(&"ring_center", rings.global_position)
			material.set_shader_parameter(&"ring_normal", rings.global_basis.y.normalized())
			material.set_shader_parameter(&"ring_texture_inner", rings.texture_inner_radius)
			material.set_shader_parameter(&"ring_texture_outer", rings.texture_outer_radius)

	# This body's own rings, if any: the body is the occluder of its rings.
	var ring_material: ShaderMaterial = _ring_materials.get(body.name)
	if ring_material:
		_feed_ring_material(body, ring_material, sun_direction, sun_angular_radius)


# Feeds the ringed body's own rings material: the body itself is the dominant
# (and, for now, only) occluder of its rings. The ring-transmission uniforms are
# intentionally left unset (default off) so the rings don't self-shadow.
func _feed_ring_material(body: IVBody, material: ShaderMaterial, sun_direction: Vector3,
		sun_angular_radius: float) -> void:
	material.set_shader_parameter(&"sun_direction", sun_direction)
	material.set_shader_parameter(&"sun_angular_radius", sun_angular_radius)
	material.set_shader_parameter(&"ambient_light", _ambient_light)
	if not _analytic_enabled:
		material.set_shader_parameter(&"occluder_count", 0)
		return
	var position := body.global_position
	var pole := body.get_north_axis()
	# Fresh arrays, not the shared scratch: set_shader_parameter aliases them (see
	# _feed_body), and this ringed body is not the only receiver in the frame.
	var occluder_data_a := PackedVector4Array()
	var occluder_data_b := PackedVector4Array()
	occluder_data_a.resize(MAX_OCCLUDERS)
	occluder_data_b.resize(MAX_OCCLUDERS)
	occluder_data_a[0] = Vector4(position.x, position.y, position.z, body.get_equatorial_radius())
	occluder_data_b[0] = Vector4(pole.x, pole.y, pole.z, body.get_polar_radius())
	material.set_shader_parameter(&"occluder_count", 1)
	material.set_shader_parameter(&"occluder_data_a", occluder_data_a)
	material.set_shader_parameter(&"occluder_data_b", occluder_data_b)


# Fills the occluder scratch arrays with the candidates whose shadow reaches the
# receiver's disc, keeping the MAX_OCCLUDERS whose shadow lands nearest the disc
# center, and returns the count. The rank key is a linear clearance at the
# receiver - how far the occluder's penumbra reaches past the receiver's limb -
# not an angular score. An angular score carries a parallax term
# atan(receiver_radius / dist) that blows up as dist shrinks, so a close-in moon
# outscores a genuinely-transiting distant one even when its own shadow is
# nowhere near the disc; with only MAX_OCCLUDERS slots that can starve the real
# transit. Clearance measures actual shadow reach, so the transiting occluder wins.
func _select_occluders(body: IVBody, body_position: Vector3, sun_direction: Vector3,
		sun_angular_radius: float) -> int:
	var receiver_radius := body.get_equatorial_radius()
	var candidates := _get_candidates(body)
	_keeper_bodies.clear()
	_keeper_scores.clear()
	for candidate: IVBody in candidates:
		var offset := candidate.global_position - body_position
		var dist := offset.length()
		var candidate_radius := candidate.get_equatorial_radius()
		if dist <= candidate_radius:
			continue
		var toward_sun := offset.dot(sun_direction)
		if toward_sun <= 0.0:
			continue # not sunward of the receiver
		# Perpendicular miss of the sun->candidate shadow axis from the receiver
		# center, vs the penumbra's outer radius where the shadow reaches it.
		var perp := sqrt(maxf(dist * dist - toward_sun * toward_sun, 0.0))
		var penumbra_radius := candidate_radius + toward_sun * sun_angular_radius
		var clearance := receiver_radius + penumbra_radius - perp
		if clearance <= 0.0:
			continue # shadow misses the receiver's disc entirely
		_keeper_bodies.append(candidate)
		_keeper_scores.append(clearance)
	var count := mini(_keeper_bodies.size(), MAX_OCCLUDERS)
	for slot in count:
		var best := slot
		for i in range(slot + 1, _keeper_bodies.size()):
			if _keeper_scores[i] > _keeper_scores[best]:
				best = i
		if best != slot:
			var swap_score := _keeper_scores[slot]
			_keeper_scores[slot] = _keeper_scores[best]
			_keeper_scores[best] = swap_score
			var swap_body := _keeper_bodies[slot]
			_keeper_bodies[slot] = _keeper_bodies[best]
			_keeper_bodies[best] = swap_body
		var occluder := _keeper_bodies[slot]
		var position := occluder.global_position
		var pole := occluder.get_north_axis()
		_occluder_data_a[slot] = Vector4(position.x, position.y, position.z,
				occluder.get_equatorial_radius())
		_occluder_data_b[slot] = Vector4(pole.x, pole.y, pole.z, occluder.get_polar_radius())
	return count


func _get_candidates(body: IVBody) -> Array:
	if _candidate_lists.has(body.name):
		return _candidate_lists[body.name]
	var candidates: Array[IVBody] = []
	var parent := body.parent
	if parent and not parent.flags & IVBody.BodyFlags.BODYFLAGS_STAR:
		if parent.mean_radius >= MIN_OCCLUDER_RADIUS:
			candidates.append(parent)
		for sibling_name: StringName in parent.satellites:
			var sibling := parent.satellites[sibling_name]
			if sibling == body or sibling.mean_radius < MIN_OCCLUDER_RADIUS:
				continue
			candidates.append(sibling)
	for satellite_name: StringName in body.satellites:
		var satellite := body.satellites[satellite_name]
		if satellite.mean_radius >= MIN_OCCLUDER_RADIUS:
			candidates.append(satellite)
	_candidate_lists[body.name] = candidates
	return candidates


# The camera-point fraction uses the camera system's bodies (the star orbiter
# itself and its satellites) plus ring transmission - the same occluders a
# co-located receiving surface would see.
func _update_camera_fraction() -> void:
	camera_sun_visible_fraction = 1.0
	var star_orbiter := _camera_star_orbiter
	if not _camera or not star_orbiter:
		return
	var star := star_orbiter.star
	if not star or star == star_orbiter:
		return
	var camera_position := _camera.global_position
	var star_vector := star.global_position - camera_position
	var star_distance := star_vector.length()
	if star_distance <= 0.0:
		return
	var sun_direction := star_vector / star_distance
	var sun_angular_radius := star.mean_radius / star_distance
	var fraction := _get_point_spheroid_fraction(star_orbiter, camera_position, sun_direction,
			sun_angular_radius)
	for satellite_name: StringName in star_orbiter.satellites:
		var satellite := star_orbiter.satellites[satellite_name]
		if satellite.mean_radius < MIN_OCCLUDER_RADIUS:
			continue
		fraction *= _get_point_spheroid_fraction(satellite, camera_position, sun_direction,
				sun_angular_radius)
	var rings: IVRings = _rings_nodes.get(star_orbiter.name)
	if rings:
		fraction *= IVAstronomy.get_ring_transmission(
				_ring_profile_images[star_orbiter.name], camera_position, sun_direction,
				sun_angular_radius, rings.global_position, rings.global_basis.y.normalized(),
				rings.texture_inner_radius, rings.texture_outer_radius)
	camera_sun_visible_fraction = fraction


func _get_point_spheroid_fraction(occluder: IVBody, position: Vector3, sun_direction: Vector3,
		sun_angular_radius: float) -> float:
	return IVAstronomy.get_spheroid_occlusion_fraction(position, sun_direction,
			sun_angular_radius, occluder.global_position, occluder.get_north_axis(),
			occluder.get_equatorial_radius(), occluder.get_polar_radius())
