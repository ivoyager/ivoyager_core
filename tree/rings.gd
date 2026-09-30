# rings.gd
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
class_name IVRings
extends MeshInstance3D

## Visual planetary rings of an [IVBody] instance.
##
## The rings cast no shadow-map shadows in either direction: ring shadows on
## bodies and body shadows on the rings are both analytic, fed per frame by
## [IVSunOcclusionManager] using this node's geometry and profile data (see
## [code]shaders/_sun_occlusion.gdshaderinc[/code]).[br][br]
##
## All properties are set from data table rings.tsv.[br][br]
##
## Uses rings.gdshader. See comments in the shader file for graphics issues
## and commentary.[br][br]
##
## Not persisted. [IVBodyFinisher] adds when [IVBody] is added to the tree.[br][br]

## How far outside the ring system the plane extends, as a fraction of the ring span.
## Pure geometry, and only outward: the shader's own aperture coverage decides where it
## draws, so nothing inside the ring needs a margin. The texture's radial extent is
## derived from the data it holds (see [member texture_inner_radius]), not from this.[br][br]
##
## This is not the room the camera's point spread function needs, which depends on the
## view and is taken by rings.gdshader's own outward expansion; all this has to do is
## keep the texture's outer edge inside the plane's inscribed circle.
const RENDER_MARGIN := 0.01

## Table columns that are also shader uniforms of the same name, forwarded verbatim.
const PHOTOMETRY_PARAMETERS: Array[StringName] = [&"back_phase", &"forward_phase",
		&"forward_level", &"forward_reddening", &"unlit_level", &"clumping",
		&"opposition_surge", &"opposition_width", &"scattering_scale"]

## Optical-depth bins the radial profile is reduced to for the point source; see
## [method _build_psf_profile]. Measured against the full 13177-texel profile over a grid
## of openings, sun elevations and phases, 64 bins hold the ring's whole flux to 0.9 % at
## worst and 0.03 % at the median — where the same count spaced LINEARLY in optical depth
## runs 76 % out.
const PSF_PROFILE_BINS := 64
## Thinnest optical depth those bins resolve. A grazing ray's answer is carried entirely by
## the thinnest material there is: at [constant MIN_MU] the slab's path rate reaches 2e4, so
## its transmission is still moving well below optical depth 1e-4.
const PSF_TAU_FLOOR := 1e-5
## rings.gdshader's own floor on the elevation sines, mirrored so the CPU's flux and the
## rendered plane's cannot part company at grazing.
const MIN_MU := 1e-4
## rings.gdshader's own cap on transmission, hence on optical depth. Mirrored for the same
## reason, and it is what fixes the bins' upper edge.
const MIN_TRANSMISSION := 0.001

## Pixel radius of the ring system's own projected image at and above which this plane
## carries all of the ring's light, and below [constant PSF_HANDOFF_LOW_PX] none of it —
## [IVBodyPSF]'s quad carrying it instead, as one more source in the body's point-source
## flux. Two things set the span. Below it, rasterizing a zero-thickness plane is simply the
## wrong instrument: measured against convolved ray casts, the drawn flux holds within 1 %
## of truth out to a 10 px outer radius, runs 5-10 % out by 3 px, and then swings 0.7 to 1.2
## before collapsing to nothing once the image falls off pixel centres entirely. Above it,
## the ring is a shape a viewer can see and must not be turned into a dot. Both halves ride
## one crossfade, so the ring's light is drawn exactly once at every distance.
const PSF_HANDOFF_HIGH_PX := 8.0
const PSF_HANDOFF_LOW_PX := 3.0

## Render height an off-screen capture is about to use, or 0.0 for none. The plane/point
## crossfade is decided in pixels and serves every viewport this node draws into, so a capture
## taller than the window would otherwise show a point where its own pixels resolve the ring:
## [IVScreenshotManager] registers its render height here, waits a frame, captures and clears
## it. The crossfade takes the greater of this and the live viewport, so a stale value can only
## hold light on the plane, never hand it to the point.
static var capture_render_height := 0.0
## Stops drawing the plane once the point has all of the ring's light in every viewport, where
## every fragment it draws would discard anyway; this is what retires a distant ring. Set false
## to render (and measure) the plane regardless. See [i]Culling, visibility and lifecycle[/i]
## in VISUAL_MODEL.md.
static var cull_handed_off := true


# All built from table rings.tsv.
## Asset file prefix used to locate ring textures.
var file_prefix: String
## Inner edge of the ring system, in simulator units.
var inner_radius: float
## Outer edge of the ring system, in simulator units.
var outer_radius: float
## Name of the [IVBody] star casting light through the rings.
var illuminating_star: StringName

# Photometry. These are the whole appearance model: rings.gdshader is generic, so a
# different real or invented ring system is a new texture and a new table row. See that
# shader's header for what each one does, and addons/tools/build_saturn_rings.py for
# where Saturn's come from.
## Phase angle of texture layer 0, in radians.
var back_phase: float
## Phase angle of texture layer 1, in radians.
var forward_phase: float
## Lit-face brightness at [member forward_phase] relative to [member back_phase].
var forward_level: float
## Red-channel multiplier at [member forward_phase].
var forward_reddening: float
## The ring system's V colour index, for its body's POINT source only — the plane itself is
## coloured by its texture. It has to be the colour that texture renders rather than
## published ring photometry, or the light changes colour as the plane hands over; re-derive
## it whenever the asset's colour changes. See [i]Rings[/i] in PHOTOMETRIC_MODEL.md.
var color_b_v: float
## Texture layer 2's level relative to layer 0.
var unlit_level: float
## Spread of optical depth across the beam, as the shape of a gamma distribution about its
## mean. Must match the value the texture was built with.
var clumping: float
## Fractional brightening added at zero phase angle.
var opposition_surge: float
## Angular e-folding width of that surge, in radians.
var opposition_width: float
## Overall level. The source profiles are peak-normalized, so nothing else sets it.
var scattering_scale: float

## Radius of the ring texture's inner edge, in simulator units: half a texel inside
## [member inner_radius], which is the radius of its first texel's centre. The shadow
## profile texture spans [member texture_inner_radius] to [member texture_outer_radius].
## Read-only!
var texture_inner_radius: float
## Radius of the ring texture's outer edge, half a texel outside [member outer_radius].
## Read-only!
var texture_outer_radius: float


var _rings_material := ShaderMaterial.new()
var _texture_array: TextureLayered # backscatter/forwardscatter/unlitside layers
var _body: IVBody
var _illuminating_star: IVBody
# The radial profile as the point source needs it; see _build_psf_profile(). Parallel
# arrays over the non-empty optical-depth bins: the bin's own optical depth, and the three
# texture layers' area-weighted luminous scattering strength in it.
var _psf_tau := PackedFloat64Array()
var _psf_back := PackedFloat64Array()
var _psf_forward := PackedFloat64Array()
var _psf_unlit := PackedFloat64Array()
var _handed_off := false # the plane's instance hidden by the handoff gate (cull_handed_off)
var _applied_plane_light_fraction := NAN # change gate; NAN forces the first write


func _init(body: IVBody) -> void:
	# threadsafe
	name = &"Rings"
	_body = body
	var row := IVTableData.db_find_in_array(&"rings", &"bodies", body.name)
	assert(row != -1, "Could not find row in rings.tsv for %s" % body.name)
	IVTableData.db_build_object(self, &"rings", row)
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	_texture_array = asset_preloader.get_rings_texture_array(name)
	cast_shadow = SHADOW_CASTING_SETTING_OFF # ring shadows are analytic; see class doc
	mesh = IVGlobal.resources[&"plane_mesh"] # shared subdivided 2x2 plane (farwarp needs subdivision)
	rotation.x = PI / 2.0 # z up astronomy


func _ready() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)

	_illuminating_star = IVBody.bodies.get(illuminating_star)
	assert(_illuminating_star, "Could not find illuminating star '%s'" % illuminating_star)

	# Distances in sim scale. The texture's texels are the source's own radial samples,
	# the first centred on inner_radius and the last on outer_radius, so its edges sit
	# half a texel outside both -- derived from the width, never a shared constant.
	var ring_span := outer_radius - inner_radius
	var texel_span := ring_span / float(_texture_array.get_width() - 1)
	texture_inner_radius = inner_radius - 0.5 * texel_span
	texture_outer_radius = outer_radius + 0.5 * texel_span
	var plane_radius := outer_radius + RENDER_MARGIN * ring_span # edge of plane

	# normalized distances from center of 2x2 plane
	var texture_start := texture_inner_radius / plane_radius
	var texture_end := texture_outer_radius / plane_radius

	scale = Vector3(plane_radius, 1.0, plane_radius)
	# Frustum culling tests the true-scale AABB, and three things in the vertex shader move
	# vertices where that AABB cannot follow: the farwarp remap keeps the ring on screen when
	# the far-plane test fails, and the edge-on tilt and the aperture's outward expansion both
	# grow the plane by view-dependent factors. Make the test always pass. That defeats a
	# distance cull too (Godot measures one from this box's collapsed centre), so the handoff
	# gate is what retires the ring (cull_handed_off).
	var extent := IVCoreSettings.max_camera_distance
	custom_aabb = AABB(-Vector3.ONE * extent, 2.0 * Vector3.ONE * extent)
	sorting_use_aabb_center = false # f32 collapses that AABB's centre; sort by the node origin

	_rings_material.shader = IVGlobal.resources[&"rings_shader"]
	_rings_material.set_shader_parameter(&"rings_textures", _texture_array)
	_rings_material.set_shader_parameter(&"texture_width", float(_texture_array.get_width()))
	_rings_material.set_shader_parameter(&"texture_start", texture_start)
	_rings_material.set_shader_parameter(&"texture_end", texture_end)
	for parameter: StringName in PHOTOMETRY_PARAMETERS:
		_rings_material.set_shader_parameter(parameter, get(parameter))
	_body.rings_psf_color_b_v = color_b_v # constant; the flux factor below is per frame
	set_surface_override_material(0, _rings_material)

	_build_psf_profile()



func _process(_delta: float) -> void:
	if !visible or !_illuminating_star: # null after _clear_procedural, before free
		if _body:
			_body.rings_psf_flux_factor = 0.0
		return

	_rings_material.set_shader_parameter(&"illumination_position",
			_illuminating_star.global_position)
	_update_psf_handoff()


func _notification(what: int) -> void:
	# The engine re-shows the instance on entering the world and on any visibility change in
	# or above this node.
	if !_handed_off:
		return
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_WORLD:
		RenderingServer.instance_set_visible(get_instance(), false)


func _clear_procedural() -> void:
	_body = null
	_illuminating_star = null


# The crossfade between this plane and the body's point-source quad, and the flux the quad
# needs to hold up its end of it. Runs every frame; the flux sum itself runs only where the
# quad is taking some of the light, which is a ring a few pixels across and nothing else.
func _update_psf_handoff() -> void:
	if !_body:
		return
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport else null
	if !camera:
		return
	var camera_distance := global_position.distance_to(camera.global_position)
	if camera_distance <= 0.0:
		return
	# The ring system's own projected image, in pixels of radius. The ramp's ends are
	# rasterization limits, so they are pixels of the 3D render buffer, which 3D render
	# scale shrinks below the window's -- and of a capture's, if that is taller (see
	# capture_render_height). pixel_angle mirrors rings.gdshader's vertex(), which takes it
	# from the same projection matrix and that buffer's VIEWPORT_SIZE.
	var render_height := maxf(IVGraphicsManager.get_render_size(viewport).y,
			capture_render_height)
	var projection := camera.get_camera_projection()
	var pixel_angle := 2.0 / maxf(render_height * absf(projection.y.y), 1e-9)
	var outer_pixels := outer_radius / (camera_distance * pixel_angle)
	var psf_fraction := 1.0 - smoothstep(PSF_HANDOFF_LOW_PX, PSF_HANDOFF_HIGH_PX,
			outer_pixels)
	var plane_light_fraction := 1.0 - psf_fraction
	if plane_light_fraction != _applied_plane_light_fraction: # 1.0 or 0.0 outside the ramp
		_applied_plane_light_fraction = plane_light_fraction
		_rings_material.set_shader_parameter(&"plane_light_fraction", plane_light_fraction)
	_set_handed_off(cull_handed_off and psf_fraction >= 1.0)
	if psf_fraction <= 0.0:
		_body.rings_psf_flux_factor = 0.0
		return
	_body.rings_psf_flux_factor = psf_fraction * _get_psf_flux_factor(
			camera.global_position, _illuminating_star.global_position)


# With no light left on the plane, rings.gdshader discards every fragment in every viewport (the
# fraction is decided at the greatest render height in use), so the plane stops drawing and its
# vertex work goes too. Through the rendering server rather than `visible`, which _process()
# reads as a project switching the ring off, and so without touching the point's share.
func _set_handed_off(handed_off: bool) -> void:
	if handed_off == _handed_off:
		return
	_handed_off = handed_off
	RenderingServer.instance_set_visible(get_instance(), !handed_off and is_visible_in_tree())


## Returns the rings' contribution to their body's POINT-SOURCE flux, in the same terms the
## body's own disc contributes [code]geometric_albedo * phase_function * radius^2[/code] —
## so multiplying by the star's illuminance at the body and dividing by the camera distance
## squared gives the illuminance the rings put at the camera.[br][br]
##
## The integral is the one rings.gdshader rasterizes,
## [code]sum S geometry(tau, mu, mu0) dA[/code] over the annulus, times the phase level and
## the projection [code]mu[/code]. Far from the body every part of the ring shares one phase
## and one pair of elevations, which is exactly the regime a point source is for, so it
## reduces to a sum over the optical-depth bins [method _build_psf_profile] left.[br][br]
##
## What it leaves out is small, and is left out of the body's own point flux too: the
## planet's shadow on the rings, the rings' shadow on the planet, and the 6 % of the globe's
## own flux the rings occult at their widest opening.
func _get_psf_flux_factor(camera_position: Vector3, star_position: Vector3) -> float:
	var bins := _psf_tau.size()
	if bins == 0:
		return 0.0
	var center := global_position
	var to_camera := camera_position - center
	var camera_distance := to_camera.length()
	if camera_distance <= 0.0:
		return 0.0
	to_camera /= camera_distance
	var to_sun := star_position - center
	if to_sun.is_zero_approx():
		return 0.0
	to_sun = to_sun.normalized()
	# The plane's own normal, taken as the shader takes it. Either sign will do: only the
	# PRODUCT of the two elevations decides which face is lit.
	var normal := global_transform.basis.y.normalized()
	var sin_camera := to_camera.dot(normal)
	var sin_sun := to_sun.dot(normal)
	var mu := maxf(absf(sin_camera), MIN_MU)
	var mu0 := maxf(absf(sin_sun), MIN_MU)
	var is_lit_face := sin_camera * sin_sun > 0.0
	# Phase, and the level and layer mix it drives; mirrors rings.gdshader's fragment().
	var phase := acos(clampf(to_sun.dot(to_camera), -1.0, 1.0))
	var phase_fraction := (phase - back_phase) / maxf(forward_phase - back_phase, 1e-4)
	var level := maxf(forward_level, 1e-6) ** phase_fraction
	level *= 1.0 + opposition_surge * exp(-phase / maxf(opposition_width, 1e-6))
	var shape_mix := clampf(phase_fraction, 0.0, 1.0)
	var total := 0.0
	if is_lit_face:
		var rate := 1.0 / mu + 1.0 / mu0
		var saturated := mu0 / (mu + mu0)
		for bin in bins:
			var strength := _psf_back[bin] + shape_mix * (_psf_forward[bin] - _psf_back[bin])
			total += strength * saturated * (1.0
					- _get_beam_transmission(_psf_tau[bin], rate))
	else:
		var sun_rate := 1.0 / mu0
		var view_rate := 1.0 / mu
		var difference := view_rate - sun_rate
		var is_limit := absf(difference) < 1e-4 * maxf(sun_rate, view_rate)
		for bin in bins:
			var optical_depth := _psf_tau[bin]
			var geometry: float
			if is_limit:
				# The 0/0 at mu == mu0, taken as the transmission's own derivative there.
				geometry = view_rate * optical_depth * _get_beam_transmission(optical_depth,
						sun_rate)
				if clumping <= 1e4:
					geometry /= 1.0 + sun_rate * optical_depth / maxf(clumping, 1e-4)
			else:
				geometry = view_rate * (_get_beam_transmission(optical_depth, sun_rate)
						- _get_beam_transmission(optical_depth, view_rate)) / difference
			total += _psf_unlit[bin] * geometry
	return total * mu * level * scattering_scale / PI


# rings.gdshader's ring_beam_transmission(): optical depth taken as gamma-distributed about
# its mean with shape `clumping`, whose large-clumping limit is exactly exp(-rate * tau).
func _get_beam_transmission(optical_depth: float, rate: float) -> float:
	if clumping > 1e4:
		return exp(-rate * optical_depth)
	return (1.0 + rate * optical_depth / clumping) ** -clumping


# The radial profile reduced to what the point source needs. The ring's whole reflected
# flux is `sum S(r) geometry(tau(r), mu, mu0) dA`, and geometry depends on radius ONLY
# through optical depth — so grouping the texels by optical depth groups them by the only
# thing that varies across the sum, and a few dozen bins stand in for the texture's
# thousands of texels.
#
# Spaced in LOG optical depth, because what the slab term is sensitive to is tau against
# 1/rate and the rate runs from 2 face on to 2e4 at the shader's grazing floor. Linear bins
# put the whole C ring and the Cassini Division in the first one, and a grazing ray's answer
# is carried by texels thinner than that bin's own mean: measured, linear bins run 76 % out
# at 64 bins and NO BETTER at 128, where log bins hold 0.9 %.
#
# Colour collapses to luminance here because the quad wants a magnitude, not a spectrum —
# its colour is the body's own color_b_v.
func _build_psf_profile() -> void:
	const LUMA_RED := 0.2126
	const LUMA_GREEN := 0.7152
	const LUMA_BLUE := 0.0722
	var width := _texture_array.get_width()
	if width < 2 or outer_radius <= inner_radius:
		return
	var layer_data: Array[PackedFloat32Array] = []
	for layer in 3:
		var image := _texture_array.get_layer_data(layer)
		if !image or image.get_width() != width:
			push_warning("IVRings: could not read %s texture layer %s; its body's point"
					% [name, layer] + " source will carry no ring light")
			return
		image.convert(Image.FORMAT_RGBAF)
		layer_data.append(image.get_data().to_float32_array())
	var log_floor := log(PSF_TAU_FLOOR)
	var log_span := log(-log(MIN_TRANSMISSION)) - log_floor
	var weights := PackedFloat64Array()
	var tau_sums := PackedFloat64Array()
	var back_sums := PackedFloat64Array()
	var forward_sums := PackedFloat64Array()
	var unlit_sums := PackedFloat64Array()
	weights.resize(PSF_PROFILE_BINS)
	tau_sums.resize(PSF_PROFILE_BINS)
	back_sums.resize(PSF_PROFILE_BINS)
	forward_sums.resize(PSF_PROFILE_BINS)
	unlit_sums.resize(PSF_PROFILE_BINS)
	var radial_step := (outer_radius - inner_radius) / (width - 1)
	for index in width:
		var offset := index * 4
		# Alpha is `1 - transmission` at normal incidence and is the same in all three
		# layers, so one optical depth serves the lot.
		var optical_depth := -log(clampf(1.0 - layer_data[0][offset + 3], MIN_TRANSMISSION, 1.0))
		var area := TAU * (inner_radius + index * radial_step) * radial_step
		var bin := int((log(maxf(optical_depth, PSF_TAU_FLOOR)) - log_floor)
				/ log_span * PSF_PROFILE_BINS)
		bin = clampi(bin, 0, PSF_PROFILE_BINS - 1)
		weights[bin] += area
		tau_sums[bin] += area * optical_depth
		back_sums[bin] += area * (layer_data[0][offset] * LUMA_RED
				+ layer_data[0][offset + 1] * LUMA_GREEN + layer_data[0][offset + 2] * LUMA_BLUE)
		forward_sums[bin] += area * (layer_data[1][offset] * forward_reddening * LUMA_RED
				+ layer_data[1][offset + 1] * LUMA_GREEN + layer_data[1][offset + 2] * LUMA_BLUE)
		unlit_sums[bin] += area * unlit_level * (layer_data[2][offset] * LUMA_RED
				+ layer_data[2][offset + 1] * LUMA_GREEN + layer_data[2][offset + 2] * LUMA_BLUE)
	for bin in PSF_PROFILE_BINS:
		if weights[bin] <= 0.0:
			continue
		_psf_tau.append(tau_sums[bin] / weights[bin])
		_psf_back.append(back_sums[bin])
		_psf_forward.append(forward_sums[bin])
		_psf_unlit.append(unlit_sums[bin])
