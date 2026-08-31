# shells_model.gd
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
class_name IVShellsModel
extends MeshInstance3D

## A body's surface model, and the orchestrator of its concentric overlay "shells".
##
## The model used for stars and planetary-mass objects that have no packed-scene
## model. It is "shell 0" (the surface — the shared sphere mesh, or a custom body mesh
## via [param mesh_override]) and the parent of optional overlay shells 1..N (cloud deck,
## atmospheric haze, limb), each a child [IVShellsModel]. Created by [IVBodyVisual].[br][br]
##
## Every shell is one shells.tsv row. A body's own shells are listed in its body-table
## [code]shells[/code] field ([code]ARRAY[STRING][/code], e.g. [code]SURFACE;CLOUDS;LIMB[/code]);
## each tag names a row [code]SHELL_<body_name>_<tag>[/code]. The row flagged
## [code]shell0[/code] is the surface; the rest are overlays. A body that lists no
## [code]shell0[/code] row takes its surface from the shells.tsv row of its
## [code]surface_class[/code] — and when it does list one, that row wholly replaces the class
## row (never a merge). Each row sets:[br]
## - [code]scale[/code] ([float]): radius multiplier, 1.0 if unset; required for an overlay
## (a value < 1.0 places the shell under the surface).[br]
## - [code]file_tag[/code] ([StringName], optional): texture filename token
## ([code]<file_prefix>.<file_tag>.<channel>[/code]); blank for a textureless shell and
## for the surface, whose textures use [code]file_prefix[/code] alone.[br]
## - [code]shader[/code] ([StringName]): give the shell a [ShaderMaterial] using the
## named [Shader] in [member IVGlobal.resources], instead of a [StandardMaterial3D].[br]
## - [code]process[/code] ([StringName]): name a [member process_methods] entry called on the
## shell each frame as [code]method(delta, ...process_args)[/code] (e.g. [method _rotate]).[br]
## - [code]process_args[/code] ([code]ARRAY[VARIANT][/code]): extra arguments bound after
## [code]delta[/code] in the [code]process[/code] call.[br]
## - [code]transparency[/code] ([enum BaseMaterial3D.Transparency]): per-shell material
## override, no shell-0 assumption. (Shadow-casting is the separate [code]cast_shadow[/code] column.)[br]
## - any other column: set directly as the named [StandardMaterial3D] property (e.g.
## [code]albedo_color[/code], [code]roughness[/code]) or shader uniform of that name. No shell
## needs a texture: [code]albedo_color[/code] (RGBA) alone is a uniform shell, and a surface
## with no color map at all takes its surface class's [code]fallback_color[/code].[br][br]
##
## Overlapping translucent shells auto-order back-to-front by scale (outer on top,
## via material [code]render_priority[/code]); give shells distinct scales (equal
## scales z-fight).[br][br]
##
## Two things reach every shader shell of a body beyond its own row. Each shader material
## receives the body's geometry as uniforms, blindly (a no-op on a shader without them):
## [code]body_radius_km[/code], [code]shell_scale[/code] (this shell's) and
## [code]surface_scale[/code] (shell 0's), which is what lets a shader work in kilometres of
## altitude above the disc. And the [code]atm_*[/code] columns of an overlay row — the limb
## shell's atmosphere — are pushed to shell 0 and every other shell as well, so the surface
## and cloud shaders redden their direct light through the same atmosphere the limb draws.
## Author them on the limb row only.[br][br]
##
## Developer note: Process methods must gate themselves on [member IVStateManager.paused_tree]
## as needed. This is because some methods need to run in a project setup where
## the camera is able to move during pause.


## Texture channel → the [enum BaseMaterial3D.Feature] enabled when that channel is
## applied (channels absent here are always active). Used by [method _apply_channels_to_material].
const CHANNEL_FEATURES := {
	BaseMaterial3D.TEXTURE_EMISSION: BaseMaterial3D.FEATURE_EMISSION,
	BaseMaterial3D.TEXTURE_NORMAL: BaseMaterial3D.FEATURE_NORMAL_MAPPING,
	BaseMaterial3D.TEXTURE_BENT_NORMAL: BaseMaterial3D.FEATURE_BENT_NORMAL_MAPPING,
	BaseMaterial3D.TEXTURE_RIM: BaseMaterial3D.FEATURE_RIM,
	BaseMaterial3D.TEXTURE_CLEARCOAT: BaseMaterial3D.FEATURE_CLEARCOAT,
	BaseMaterial3D.TEXTURE_FLOWMAP: BaseMaterial3D.FEATURE_ANISOTROPY,
	BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION: BaseMaterial3D.FEATURE_AMBIENT_OCCLUSION,
	BaseMaterial3D.TEXTURE_HEIGHTMAP: BaseMaterial3D.FEATURE_HEIGHT_MAPPING,
	BaseMaterial3D.TEXTURE_SUBSURFACE_SCATTERING: BaseMaterial3D.FEATURE_SUBSURFACE_SCATTERING,
	BaseMaterial3D.TEXTURE_SUBSURFACE_TRANSMITTANCE: BaseMaterial3D.FEATURE_SUBSURFACE_TRANSMITTANCE,
	BaseMaterial3D.TEXTURE_BACKLIGHT: BaseMaterial3D.FEATURE_BACKLIGHT,
	BaseMaterial3D.TEXTURE_REFRACTION: BaseMaterial3D.FEATURE_REFRACTION,
	BaseMaterial3D.TEXTURE_DETAIL_ALBEDO: BaseMaterial3D.FEATURE_DETAIL,
}

## Material value property → the [enum BaseMaterial3D.Feature] enabled when that
## property is set from a data table — the non-texture analog of [constant CHANNEL_FEATURES],
## so setting e.g. [code]rim[/code] enables [code]rim_enabled[/code] automatically.
const PROPERTY_FEATURES := {
	&"emission": BaseMaterial3D.FEATURE_EMISSION,
	&"normal_scale": BaseMaterial3D.FEATURE_NORMAL_MAPPING,
	&"rim": BaseMaterial3D.FEATURE_RIM,
	&"rim_tint": BaseMaterial3D.FEATURE_RIM,
	&"clearcoat": BaseMaterial3D.FEATURE_CLEARCOAT,
	&"clearcoat_roughness": BaseMaterial3D.FEATURE_CLEARCOAT,
	&"anisotropy": BaseMaterial3D.FEATURE_ANISOTROPY,
	&"ao_light_affect": BaseMaterial3D.FEATURE_AMBIENT_OCCLUSION,
	&"heightmap_scale": BaseMaterial3D.FEATURE_HEIGHT_MAPPING,
	&"subsurf_scatter_strength": BaseMaterial3D.FEATURE_SUBSURFACE_SCATTERING,
	&"subsurf_scatter_transmittance_color": BaseMaterial3D.FEATURE_SUBSURFACE_TRANSMITTANCE,
	&"backlight": BaseMaterial3D.FEATURE_BACKLIGHT,
	&"refraction_scale": BaseMaterial3D.FEATURE_REFRACTION,
}

const _SUN_DISC_BRIGHTNESS := 3.0 # nonphysical disc level; physical light derives it instead


## Registry of 'process' methods, keyed by the name used in a shells.tsv
## 'process' field. Each [Callable] runs on the shell every frame as
## [code]method(shells_model, delta, ...process_args)[/code]. Register entries in
## [method _static_init] or from project code to add a process method without subclassing.
static var process_methods: Dictionary[StringName, Callable] = {}

# Debug-only caches for the per-shell override asserts in _build_material; built
# lazily and kept for the session. Unused unless OS.is_debug_build().
static var _material_property_names: Dictionary[StringName, bool] = {}
static var _shader_uniform_names: Dictionary = {} # Shader -> Dictionary[StringName, bool]

var _shell: int # 0 is the surface and orchestrator; 1..N are child shells
var _body_name: StringName
var _mean_radius: float
var _process_callable: Callable
var _body: IVBody # owning body, for its true (un-farwarped) position and its published handoff
var _applies_psf: bool # this body draws an IVBodyPSF, so this shell fades at the handoff
var _disc_material: ShaderMaterial # the shell's own material, LOD-driven each frame
var _is_sun: bool # sun-mode (shell 0 with is_sun); see the disc LOD section
var _sun_bv := 0.63 # sun-mode: cached B-V (disc color); fallback if the characteristic is missing
var _sun_abs_mag := 4.83 # sun-mode: cached V absolute magnitude (for the disc's surface brightness)
var _psf_settings: IVPSFSettings # sun-mode: the shared PSF camera (color ramp only, here)
var _applied_sun_disc_brightness := NAN # sun-mode: change gate; NAN forces the first-frame write

var _times := IVGlobal.times




# *****************************************************************************
# 'process' methods & registry

# process_methods maps a shells.tsv 'process' name to one of the static methods
# below, resolved once per shell in _resolve_process() and called every frame via _process_callable
# as method(shells_model, delta, ...process_args). Each method owns the shell's whole per-frame
# behavior (there is no default to fall through to). Add entries without subclassing.

static func _static_init() -> void:
	process_methods[&"_rotate"] = _rotate


## Named by a shells.tsv 'process' field. Rotates [param shells_model]
## at [param deg_per_sec] degrees per second.
static func _rotate(shells_model: IVShellsModel, delta: float, deg_per_sec: float) -> void:
	const CONVERSION := PI / (180.0 * IVUnits.SECOND)
	if IVStateManager.paused_tree:
		return
	delta *= shells_model._times[1] / Engine.time_scale
	shells_model.rotate_y(delta * deg_per_sec * CONVERSION) # y up in model self reference


func _init(body_name: StringName, mean_radius: float, model_basis: Basis,
		shell := 0, mesh_override: Mesh = null) -> void:
	_body_name = body_name
	_mean_radius = mean_radius
	_shell = shell
	name = &"ShellsModel" if shell == 0 else StringName("Shell_%d" % shell)
	transform.basis = model_basis
	# shell 0 may replace the shared sphere with the body's own mesh, or its surface class's
	mesh = mesh_override if mesh_override else IVGlobal.resources[&"sphere_mesh"] as Mesh


func _ready() -> void:
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	var shell_specs := asset_preloader.get_body_shell_specs(_body_name)
	var spec: Dictionary = shell_specs[_shell]
	# Resolved before _set_visibility_and_layers(), which gates the distance cull on it.
	_body = IVBody.bodies.get(_body_name)
	_applies_psf = IVBodyPSF.is_applicable(_body)
	if _shell == 0:
		_is_sun = spec[&"is_sun"]
		# A surface need not sit at the body's mean radius: what we see of Venus is its cloud
		# top, ~65 km up. Scaled here rather than in [IVBodyVisual] so that node's
		# reference_basis stays the true body frame for rings and any other child.
		# (Overlay shells arrive pre-scaled from [method _build_child_shells].)
		var surface_scale: float = spec[&"scale"]
		if surface_scale != 1.0:
			transform.basis = transform.basis.scaled(Vector3.ONE * surface_scale)
	var process_method: StringName = spec[&"process"]
	var process_args: Array = spec[&"process_args"]
	var render_priority := _compute_render_priority(shell_specs)
	_build_material(spec, asset_preloader, render_priority)
	_apply_shell_geometry_uniforms(spec, shell_specs)
	cast_shadow = spec[&"cast_shadow"]
	_set_visibility_and_layers()
	_resolve_process(process_method, process_args)
	_enter_disc_lod()
	if _is_sun:
		_enter_sun_mode()
	if _shell == 0:
		_build_child_shells(shell_specs)
		_propagate_atmosphere_overrides(shell_specs)


func _process(delta: float) -> void:
	if _process_callable.is_valid():
		_process_callable.call(self, delta)
	if _applies_psf:
		_process_disc_lod()
	if _is_sun:
		_process_sun_physical_light()



# *****************************************************************************
# disc LOD (a body that draws an IVBodyPSF), and sun-mode within it

# A body spans many decades of viewing distance: near, it is a resolved sphere (this model's
# disc); far, it shrinks below a pixel and must become a point on the same photometric
# footing as the background star field. That point is the body's IVBodyPSF quad, and this
# is the disc's half of the trade -- the two crossfade by the body's on-screen pixel radius,
# so neither a vanishing sub-pixel disc nor the fixed distance cull it used to take occurs.
# Both halves ride one handoff, solved by IVBodyPSF and published on IVBody.psf_handoff;
# solving it twice is how they would come to disagree.
#
# EVERY shell of such a body leaves on the same weight: an overlay deck left drawn over a
# point would be the whole body's silhouette in cloud. Each shell drives itself rather than
# shell 0 recursing, matching _set_visibility_and_layers -- so IVBodyVisual need not know the
# shell structure, and an overlay built late needs no catching up.
#
# HOW a shell leaves depends on which pass it is already in, and the difference is not
# cosmetic. A lit SURFACE is opaque and must stay so -- writing ALPHA would move it to the
# transparent pass, where it stops writing depth and stops occluding anything -- so it
# discards at one threshold, which IVBodyPSF supplies by collapsing the ramp for a lit body.
# An already-transparent shell (a cloud deck, a limb, an emissive star disc) can afford to
# fade, and does.
#
# Either way it happens in the shaders, which resolve the threshold against their own
# VIEWPORT_SIZE; only what distance alone determines is set here (angular size). Nothing
# viewport-dependent is on this side on purpose -- a CPU answer could only ever suit the
# viewport this node lives in, and would leak that into an off-screen capture rendered at
# another size.
#
# SUN-MODE (shell 0 with is_sun) adds what only a star needs on this side: the disc holds a
# constant surface brightness, derived from the star's own luminosity under physical light,
# where a lit body's comes from the light that reaches it.


func _enter_disc_lod() -> void:
	# Resolved even without a quad: sun-mode drives this same material, and the disc's own
	# surface brightness must not depend on whether the point half is enabled.
	var material := get_surface_override_material(0)
	if material is ShaderMaterial:
		_disc_material = material
	if !_applies_psf:
		return
	if !_disc_material:
		# Benign but wasteful: with no handoff to fade on (and the distance cull dropped for
		# this body) the disc draws at every distance, sub-pixel and contributing nothing,
		# under the quad that has taken over. No shipped body reaches this.
		push_warning("Body %s shell %d draws an IVBodyPSF but has no ShaderMaterial to"
				% [_body_name, _shell] + " fade; it will not hand off")
	# The empty 'process' column leaves idle processing off; the LOD driver needs it on.
	set_process(true)


func _enter_sun_mode() -> void:
	if _body:
		var color_bv: float = _body.characteristics.get(&"color_b_v", _sun_bv)
		var absolute_magnitude: float = _body.characteristics.get(&"absolute_magnitude",
				_sun_abs_mag)
		_sun_bv = color_bv
		_sun_abs_mag = absolute_magnitude
	# Connected here rather than in _ready(): this model can be torn down and re-added, and
	# _ready() would not fire again, so connecting there would stack a second connection onto
	# the same settings object.
	_psf_settings = IVGlobal.program[&"PSFSettings"]
	_psf_settings.changed.connect(_on_psf_settings_changed)
	if _disc_material:
		_disc_material.set_shader_parameter(&"color_bv", _sun_bv)
		# Nonphysical placeholder; the first LOD frame applies the mode-correct
		# value (physical light derives the star's true surface brightness).
		_disc_material.set_shader_parameter(&"brightness", _SUN_DISC_BRIGHTNESS)
		_psf_settings.apply_color_to(_disc_material)
	set_process(true)


func _process_disc_lod() -> void:
	if !_disc_material:
		return
	var viewport := get_viewport()
	if !viewport:
		return
	var camera := viewport.get_camera_3d()
	if !camera:
		return
	# True (un-farwarped) distance: this model sits at the body's true position (farwarp is a
	# per-vertex shader remap), so the body's own global_position gives the real distance.
	var camera_distance := _body.global_position.distance_to(camera.global_position)
	if camera_distance <= 0.0:
		return
	# The body's mean radius, not this shell's scaled one: the whole body fades as one thing,
	# and a deck 0.16 % out would otherwise cross the ramp at a slightly different distance.
	_disc_material.set_shader_parameter(&"angular_radius", _mean_radius / camera_distance)
	var handoff := _body.psf_handoff
	_disc_material.set_shader_parameter(&"handoff_low", handoff.x)
	_disc_material.set_shader_parameter(&"handoff_high", handoff.y)


# Keeps a star disc's brightness in step with IVExposureManager. Change-gated
# writes; the NAN-initialized cache makes the first frame after (re)build apply
# the mode-correct value before first render, and makes a deactivation restore
# the nonphysical constant.
func _process_sun_physical_light() -> void:
	if !_disc_material:
		return
	var disc_brightness := _SUN_DISC_BRIGHTNESS
	if IVExposureManager.physical_active and IVExposureManager.gain > 0.0:
		disc_brightness = (IVPhotometry.get_star_disc_luminance(_sun_abs_mag, _mean_radius)
				* IVExposureManager.gain)
	if disc_brightness == _applied_sun_disc_brightness:
		return
	_applied_sun_disc_brightness = disc_brightness
	_disc_material.set_shader_parameter(&"brightness", disc_brightness)


func _on_psf_settings_changed() -> void:
	if _disc_material:
		_psf_settings.apply_color_to(_disc_material) # the disc shares only the B-V ramp



func _build_material(spec: Dictionary, asset_preloader: IVAssetPreloader,
		render_priority: int) -> void:
	var channels: Dictionary = spec[&"channels"]
	var channel_ranges: Dictionary = spec.get(&"channel_ranges", {})
	var overrides: Dictionary = spec[&"overrides"]
	var shader_name: StringName = spec[&"shader"]
	# Present only on a surface with no color map (see IVAssetPreloader). Applied under the
	# overrides, so a table albedo_color still wins; on the shader path it is a no-op for a
	# shader without the uniform, which is what leaves a mapless star its own fallback.
	var fallback_color: Variant = spec.get(&"fallback_color")
	if shader_name:
		_build_shader_material(shader_name, channels, overrides, asset_preloader,
				render_priority, fallback_color, channel_ranges)
		return
	var material := StandardMaterial3D.new()
	material.render_priority = render_priority
	if fallback_color != null:
		material.albedo_color = fallback_color
	# spec already holds the resolved shell-0 (or overlay) material columns; no merge.
	_assert_overrides_are_properties(overrides)
	_apply_material_fields(material, overrides)
	_apply_channels_to_material(material, channels)
	set_surface_override_material(0, material)


func _build_shader_material(shader_name: StringName, channels: Dictionary,
		overrides: Dictionary, asset_preloader: IVAssetPreloader, render_priority: int,
		fallback_color: Variant, spec_channel_ranges: Dictionary) -> void:
	# A shell may opt into a ShaderMaterial (its shells.tsv "shader" column naming a
	# Shader in IVGlobal.resources). Discovered channel textures feed it as named
	# uniforms, and each shells.tsv override column feeds the uniform of the same name
	# (so e.g. a "clouds_detail_strength" column tunes the shader per body); a column
	# that isn't a uniform is ignored. The shader owns its own blending.
	# When the discovered channels are Cubemaps, swap the table-named shader for its
	# cubemap variant (the asset format decides; the tables stay format-agnostic).
	if _channels_are_cube(channels):
		if asset_preloader.cube_shader_variants.has(shader_name):
			shader_name = asset_preloader.cube_shader_variants[shader_name]
		else:
			push_warning("Body %s shell %d: Cubemap channels but shader '%s' has no cube variant"
					% [_body_name, _shell, shader_name])
	var resource: Resource = IVGlobal.resources.get(shader_name)
	var shader := resource as Shader
	if not shader:
		push_warning("Body %s shell %d: shader '%s' not in IVGlobal.resources"
				% [_body_name, _shell, shader_name])
		return
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = render_priority
	if fallback_color != null:
		material.set_shader_parameter(&"albedo_color", fallback_color)
	_apply_channels_to_shader_material(material, channels, asset_preloader)
	_apply_channel_ranges_to_shader_material(material,
			spec_channel_ranges, asset_preloader)
	_assert_overrides_are_uniforms(overrides, shader)
	_apply_overrides_to_shader_material(material, overrides)
	set_surface_override_material(0, material)


func _channels_are_cube(channels: Dictionary) -> bool:
	# A shell's channels are all one texture format — a shader is samplerCube or
	# sampler2D, not both. Return whether they are cubemaps; a mix is a bake/asset error.
	# Test TextureLayered, NOT Cubemap: an imported cubemap is a CompressedCubemap, which
	# derives from CompressedTextureLayered and is not a Cubemap (they are siblings), so
	# `is Cubemap` silently misses every imported cubemap and routes it to the 2D shader.
	var any_cube := false
	var any_2d := false
	for param: int in channels:
		if channels[param] is TextureLayered:
			any_cube = true
		else:
			any_2d = true
	assert(not (any_cube and any_2d),
			"Body %s shell %d: channels mix cubemap and Texture2D (a shell must be all one format)"
			% [_body_name, _shell])
	return any_cube


func _apply_channels_to_material(material: BaseMaterial3D, channels: Dictionary) -> void:
	for param: int in channels:
		var texture: Texture2D = channels[param]
		if not texture:
			continue
		material.set_texture(param, texture)
		if CHANNEL_FEATURES.has(param):
			var feature: int = CHANNEL_FEATURES[param]
			material.set_feature(feature, true)


func _apply_channels_to_shader_material(material: ShaderMaterial, channels: Dictionary,
		asset_preloader: IVAssetPreloader) -> void:
	# Feed each discovered channel texture as a shader uniform named by its
	# asset_preloader.texture_channels tag (e.g. &"albedo", &"normal").
	var texture_channels: Dictionary[int, StringName] = asset_preloader.texture_channels
	for param: int in channels:
		var texture: Texture = channels[param] # Texture2D (equirect) or TextureLayered (cube)
		if texture and texture_channels.has(param):
			var tag: StringName = texture_channels[param]
			material.set_shader_parameter(tag, texture)
			# Presence flag so a cube shader can fall back for absent optional channels
			# (no-op on shaders without the uniform, e.g. the equirect path).
			material.set_shader_parameter(StringName("has_%s" % tag), true)


func _apply_channel_ranges_to_shader_material(material: ShaderMaterial,
		channel_ranges: Dictionary, asset_preloader: IVAssetPreloader) -> void:
	# A range-tagged texture stores (physical - lo) / (hi - lo), so the shader has to undo
	# that to get physical light back; see IVAssetPreloader.parse_range_tags. Feed the pair
	# as "<tag>_range_lo"/"<tag>_range_hi" (e.g. "albedo_range_lo"). A shader without those
	# uniforms ignores them, and an untagged texture never reaches here at all, so both the
	# defaults and the untouched assets keep rendering exactly as before.
	var texture_channels: Dictionary[int, StringName] = asset_preloader.texture_channels
	for param: int in channel_ranges:
		if not texture_channels.has(param):
			continue
		var tag: StringName = texture_channels[param]
		var range_pair: Array = channel_ranges[param]
		material.set_shader_parameter(StringName("%s_range_lo" % tag), range_pair[0])
		material.set_shader_parameter(StringName("%s_range_hi" % tag), range_pair[1])


func _apply_overrides_to_shader_material(material: ShaderMaterial, overrides: Dictionary) -> void:
	# Each shells.tsv override column sets the shader uniform of the same name. An
	# override that isn't a uniform is a silent no-op (debug builds flag it first; see
	# _assert_overrides_are_uniforms).
	for property: StringName in overrides:
		material.set_shader_parameter(property, overrides[property])


func _apply_material_fields(material: BaseMaterial3D, fields: Dictionary) -> void:
	# Set each property, then auto-enable its feature so a table never needs a
	# *_enabled toggle (setting e.g. rim enables rim_enabled). See PROPERTY_FEATURES.
	for property: StringName in fields:
		material.set(property, fields[property])
		if PROPERTY_FEATURES.has(property):
			var feature: int = PROPERTY_FEATURES[property]
			material.set_feature(feature, true)


func _assert_overrides_are_properties(overrides: Dictionary) -> void:
	# Debug guard for a non-shader shell: its override columns are set() blindly on a
	# StandardMaterial3D, which no-ops an unknown property — so catch a typo'd or
	# unsupported shells.tsv column here. This per-shell check (with the
	# resolved shader available) is why there is no table-wide material validation.
	if not OS.is_debug_build():
		return
	if _material_property_names.is_empty():
		for property: Dictionary in StandardMaterial3D.new().get_property_list():
			var usage: int = property[&"usage"]
			if usage & PROPERTY_USAGE_DEFAULT:
				var property_name: String = property[&"name"]
				_material_property_names[StringName(property_name)] = true
	for field: StringName in overrides:
		assert(_material_property_names.has(field),
				"Body %s shell %d: shells.tsv column '%s' is not a StandardMaterial3D property"
				% [_body_name, _shell, field])


func _assert_overrides_are_uniforms(overrides: Dictionary, shader: Shader) -> void:
	# Debug guard for a shader shell: its override columns set_shader_parameter()
	# blindly, a silent no-op for an unknown uniform — so catch a typo'd shells.tsv
	# column against this specific shader's uniforms.
	if not OS.is_debug_build():
		return
	if not _shader_uniform_names.has(shader):
		var names: Dictionary[StringName, bool] = {}
		for uniform: Dictionary in shader.get_shader_uniform_list():
			var uniform_name: String = uniform[&"name"]
			names[StringName(uniform_name)] = true
		_shader_uniform_names[shader] = names
	var uniform_names: Dictionary = _shader_uniform_names[shader]
	for field: StringName in overrides:
		assert(uniform_names.has(field),
				"Body %s shell %d: shells.tsv column '%s' is not a uniform of shader '%s'"
				% [_body_name, _shell, field, shader.resource_path.get_file()])


func _set_visibility_and_layers() -> void:
	# Each shell self-configures (vs. a parent recursing) so [IVBodyVisual] need
	# not know the shell structure. Mirrors the packed-model path's settings.
	# A body with an IVBodyPSF owns its disc's visibility via the pixel-radius fade, so it
	# opts out of the fixed distance cull. That cull is zoom-blind (it would clip a still
	# resolved disc when zooming in) and, at 4000 radii, fires several times FARTHER out than
	# the handoff does -- so for these bodies it is unreachable anyway. It stays for every
	# body without a quad, which has nothing to hand off to.
	if not _applies_psf:
		visibility_range_end = _mean_radius * IVCoreSettings.radius_multiplier_visibility_range_end
	var node_layers := IVCoreSettings.get_visualinstance3d_layer_for_size(_mean_radius)
	if _is_local_shadow_caster():
		node_layers |= IVGlobal.LOCAL_SHADOW_CASTER
	layers = node_layers
	if IVCoreSettings.apply_farwarp:
		# Frustum culling tests the true-scale AABB against the far plane, but the farwarp vertex
		# remap keeps the surface on-screen even when that test fails; make it always pass.
		var extent := IVCoreSettings.max_camera_distance
		custom_aabb = AABB(-Vector3.ONE * extent, 2.0 * Vector3.ONE * extent)


# A shell that readies after a dynamic grant would miss the caster bit until
# the next state change (the ancestor's recursion is change-gated), so adopt
# the ancestor IVBodyVisual's current state; static rule when there is none
# (e.g., a replacement body visual class).
func _is_local_shadow_caster() -> bool:
	var node := get_parent()
	while node:
		var ancestor_body_visual := node as IVBodyVisual
		if ancestor_body_visual:
			return ancestor_body_visual.is_local_shadow_caster()
		node = node.get_parent()
	return IVCoreSettings.get_static_local_shadow_caster(_mean_radius)


func _build_child_shells(shell_specs: Array) -> void:
	# Each extra shell is a translucent child reusing the shared sphere mesh at a
	# larger (or smaller) radius, inheriting the body's oblateness, orientation and spin.
	# Every table scale is measured against the body, but a child's transform composes with
	# this one's — so divide out the surface's own scale to keep the two frames the same.
	var surface_scale: float = shell_specs[0][&"scale"]
	for shell_index in range(1, shell_specs.size()):
		var spec: Dictionary = shell_specs[shell_index]
		var channels: Dictionary = spec[&"channels"]
		var overrides: Dictionary = spec[&"overrides"]
		var shader: StringName = spec[&"shader"]
		# A shell needs an appearance source (texture, material override or shader);
		# otherwise it would render as an opaque white sphere.
		if channels.is_empty() and overrides.is_empty() and not shader:
			push_warning("Body %s shell %d has no texture, material override or shader; skipping"
					% [_body_name, shell_index])
			continue
		var shell_scale: float = spec[&"scale"]
		var child_basis := Basis().scaled(Vector3.ONE * shell_scale / surface_scale)
		add_child(IVShellsModel.new(_body_name, _mean_radius, child_basis, shell_index))


func _apply_shell_geometry_uniforms(spec: Dictionary, shell_specs: Array) -> void:
	# A shader that works in altitude needs to know what a local unit is: set blindly, the
	# convention for uniforms a shader may not declare (a no-op on one that does not).
	var material := get_surface_override_material(0) as ShaderMaterial
	if not material:
		return
	var shell_scale: float = spec[&"scale"]
	var surface_scale: float = shell_specs[0][&"scale"]
	material.set_shader_parameter(&"body_radius_km", _mean_radius / IVUnits.KM)
	material.set_shader_parameter(&"shell_scale", shell_scale)
	material.set_shader_parameter(&"surface_scale", surface_scale)


func _propagate_atmosphere_overrides(shell_specs: Array) -> void:
	# The atmosphere is authored once, on the limb row, and every shader shell of the body
	# needs it: the limb draws it, and the surface and cloud shaders redden their direct light
	# through it. Push each overlay row's atm_* columns to shell 0 and to every child (blind
	# sets, as above). Runs after the children exist, which add_child guarantees.
	var atmosphere: Dictionary[StringName, Variant] = {}
	for shell_index in range(1, shell_specs.size()):
		var overrides: Dictionary = shell_specs[shell_index][&"overrides"]
		for field: StringName in overrides:
			if field.begins_with("atm_"):
				atmosphere[field] = overrides[field]
	if atmosphere.is_empty():
		return
	var materials: Array[ShaderMaterial] = []
	var own := get_surface_override_material(0) as ShaderMaterial
	if own:
		materials.append(own)
	for child in get_children():
		var shell := child as IVShellsModel
		if not shell:
			continue
		var child_material := shell.get_surface_override_material(0) as ShaderMaterial
		if child_material:
			materials.append(child_material)
	for material in materials:
		for field: StringName in atmosphere:
			material.set_shader_parameter(field, atmosphere[field])


# Render priority = this shell's rank by scale (ascending; shell index breaks ties),
# so overlapping translucent shells blend back-to-front (outer over inner). The
# surface (shell 0) ranks as scale 1.0.
func _compute_render_priority(shell_specs: Array) -> int:
	var my_spec: Dictionary = shell_specs[_shell]
	var my_scale := _spec_scale(my_spec)
	var priority := 0
	for i in shell_specs.size():
		if i == _shell:
			continue
		var other_spec: Dictionary = shell_specs[i]
		var other_scale := _spec_scale(other_spec)
		if other_scale < my_scale or (other_scale == my_scale and i < _shell):
			priority += 1
	return priority


func _spec_scale(spec: Dictionary) -> float:
	var shell_scale: float = spec[&"scale"]
	return shell_scale


func _resolve_process(method: StringName, process_args: Array) -> void:
	# The 'process' field names a process_methods entry called on this shell each frame as
	# method(shells_model, delta, ...process_args) (extra args from the 'process_args' field).
	# Defining _process() enables idle processing by default, so disable it on a shell with no
	# (or an unregistered) process method.
	set_process(false)
	if not method:
		return
	var callable: Callable = process_methods.get(method, Callable())
	if not callable.is_valid():
		push_warning("Body %s shell %d: process names unregistered method '%s'"
				% [_body_name, _shell, method])
		return
	_process_callable = callable.bindv(process_args)
	set_process(true)




# *****************************************************************************
# static preview


## Scales a static preview's disc to the preview camera, given its distance to the body.
## Call again whenever that camera moves; [method set_static_preview] applies it once and stops
## the per-frame update that would otherwise maintain it. Without a live value a star's
## photosphere detail — granulation, sunspot groups, faculae — fades out entirely and the disc
## renders flat. No-op on a shell with no LOD-driven disc.
func set_preview_camera_distance(camera_distance: float) -> void:
	if !_applies_psf or !_disc_material or camera_distance <= 0.0:
		return
	_disc_material.set_shader_parameter(&"angular_radius", _mean_radius / camera_distance)


## Detaches this shell from the live simulation so it can be staged elsewhere as a still
## image: it stops animating, stops reaching outside its own subtree, and renders as a plain
## resolved disc instead of the distance-driven disc/point crossfade.
## Call on a model built for anything other than the body it belongs to — an icon capture,
## a thumbnail, a GUI preview — right after adding it to the tree, before it can process a
## frame. One way: there is no restoring the live behavior afterward. Overlay shells are
## separate models and each needs its own call ([method IVBodyVisual.set_static_preview]
## covers a whole visual).[br][br]
##
## [param camera_distance] is the preview camera's distance to the body; see
## [method set_preview_camera_distance], which this applies once.
func set_static_preview(camera_distance: float) -> void:
	# Idle processing is the only thing here that reaches outside this node: _rotate would
	# animate the shell against sim time, and _process_disc_lod would read the REAL body's
	# position and size the disc against a camera in a different World3D.
	set_process(false)
	if _is_sun and _psf_settings:
		# IVPSFSettings is shared with the live scene, so any edit to it would re-apply the
		# B-V ramp over the overrides below.
		if _psf_settings.changed.is_connected(_on_psf_settings_changed):
			_psf_settings.changed.disconnect(_on_psf_settings_changed)
	if not _applies_psf or not _disc_material:
		return
	# The disc's alpha is a crossfade against its own on-screen pixel radius, and only
	# _process_disc_lod knows how to measure that; with it off, angular_radius keeps the
	# shader default and every fragment discards. Negative edges saturate the crossfade
	# instead, so the disc always renders whatever the preview camera's distance.
	_disc_material.set_shader_parameter(&"handoff_low", -2.0)
	_disc_material.set_shader_parameter(&"handoff_high", -1.0)
	# Saturating the crossfade is not all angular_radius was feeding. On a star it also carries
	# the disc's on-screen scale to the photosphere, whose every alias fade is written against
	# px per radian, so the shader default renders granulation, spots and faculae faded fully
	# out -- an identically flat disc. A preview must supply a distance of its own.
	set_preview_camera_distance(camera_distance)
	if not _is_sun:
		return
	# DISC_BRIGHTNESS is HDR for a scene that tonemaps. Read back into an RGBA8 image it would
	# clip to white and take the B-V tint with it.
	_disc_material.set_shader_parameter(&"brightness", 1.0)
