# body_psf.gd
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
class_name IVBodyPSF
extends MeshInstance3D

## The camera's point spread function (PSF) applied to one [IVBody]'s flux, on a quad.
##
## A PSF is the imaging system's response to a point of light, and the "point" names
## that impulse rather than the subject: convolving an extended source with it is what
## puts a glow around a crescent. So this stands whether the body is resolved or not.
## [code]body_psf.gdshader[/code] draws the Gaussian PSF core, the [code]r^-2[/code]
## glare wing and the sky side of the body's own rim on one camera-facing quad.[br][br]
##
## Unresolved, this quad IS the body — the core takes the disc handoff below, so a
## body that shrinks past its disc becomes a photometric point on the catalog star
## field's own footing instead of vanishing at a distance cull. Resolved, the WING
## persists (glare belongs to the camera, not to the subject) and is what renders
## crescent glow, and the RIM's spread beyond the silhouette is drawn here because
## this is the one item that covers the sky beside a body's limb — the surface can
## image its rim through the camera's PSF but has no fragment to put the outward half
## on. One mechanism, four jobs.[br][br]
##
## A direct child of its [IVBody] rather than of [IVBodyVisual], and that is
## load-bearing: a lazy body has no visual until the camera visits it, so a quad
## hosted inside the model could not draw the far regime — which is the whole
## point. It is not [code]top_level[/code]; farwarp is a per-vertex shader remap, so
## it rides the origin shift like any tree child.[br][br]
##
## Built by [IVBodyFinisher] for every body [method is_applicable] accepts: an
## in-scene star, or a planetary-mass object with a geometric albedo. A star's
## magnitude comes from its own luminosity, a sunlit body's from its albedo, phase
## and the two distances. Everything viewport-dependent stays in the shader — a CPU
## answer could only ever suit the viewport this node lives in and would leak that
## into an off-screen capture.[br][br]
##
## Publishes [member IVBody.psf_handoff] each frame, which the body's
## [IVShellsModel] shells read so the disc leaves at exactly the pixel radius this
## quad's core arrives at.


const BodyFlags := IVBody.BodyFlags

# Handoff ramp. Solved rather than authored (see [method solve_handoff]), then shared
# with the disc: a disc's fade-out and this quad's core fade-in are two ends of one
# trade and must come from one answer.
const HANDOFF_LOW_RATIO := 0.4 # fade span, as a fraction of the solved handoff
# A LIT body's disc cannot crossfade. Fading it means writing ALPHA, which moves the
# surface to the transparent pass, where it stops writing depth and stops occluding
# anything (the star field through a night side, bodies not sorting against each other,
# the body's own quad drawing through it), and depth_draw_always is no escape: it would
# punch the quad's core out of the middle of its own crossfade. So a lit disc discards at
# one threshold instead, and this collapses the ramp to meet it there. Not exactly 1.0 --
# smoothstep's two edges must differ, and 0.1 % of a pixel radius is a step.
const HANDOFF_STEP_RATIO := 0.999
const HANDOFF_FALLBACK := 2.5 # px radius, if the source never saturates (see the solver)
const HANDOFF_REFRESH_RATIO := 1.07 # ~0.1 EV / 0.07 mag; past this the handoff re-solves

const FIVE_OVER_LN10 := 2.1714724095162594 # 5 / ln(10), for m = M + 5*log10(d)


var _body: IVBody
var _star: IVBody
var _is_sun: bool
var _draws_rim: bool # false for a star, and for a body the table figure does not outline
var _mean_radius: float
var _equatorial_radius: float
var _polar_radius: float
var _geometric_albedo: float # 0.0 for a star, which emits rather than reflects
var _lunar_lambert: float # phase-function blend; the surface shader's own L
var _absolute_magnitude := NAN # star only
var _color_bv := 0.63
var _material: ShaderMaterial
var _psf_settings: IVPSFSettings
var _applied_exposure := NAN # change gate; NAN forces the first-frame solve
var _applied_unit_magnitude := NAN # ditto (phase and heliocentric distance move it)



## Returns whether [param body] gets a quad: an in-scene star, or a planetary-mass
## object with a positive geometric albedo. This is also the gate on the fixed
## distance cull ([IVBodyVisual], [IVShellsModel]) and on a disc's handoff fade — a
## body drawn as a point must not also be culled as a disc, and one that is culled
## must not fade.[br][br]
##
## The mechanism itself is magnitude-gated, not taxonomic: the size law in
## [code]_point_spread_function.gdshaderinc[/code] shrinks a source to nothing exactly where it
## drops below one 8-bit step. The flag here is only the shipped SCOPE, and widening
## it is this one line plus the table data any new body would need.
static func is_applicable(body: IVBody) -> bool:
	if !IVCoreSettings.apply_body_psf or !body:
		return false
	if body.flags & BodyFlags.BODYFLAGS_STAR:
		return true
	return (bool(body.flags & BodyFlags.BODYFLAGS_PLANETARY_MASS_OBJECT)
			and get_geometric_albedo(body) > 0.0)


## Returns [param body]'s geometric albedo from its table [code]albedo[/code], or
## 0.0 where absent (an empty cell reaches characteristics as a non-positive float,
## not a missing key).[br][br]
##
## NOT [member IVExposureManager.default_albedo] and NOT [code]meter_albedo[/code].
## Metering wants the reflectance the camera sees, which a body's shells add to;
## this wants the GEOMETRIC albedo, which is defined by the zero-phase relation
## [method IVPhotometry.get_reflected_apparent_magnitude] inverts. Two albedos, two
## jobs. A body without one gets no quad rather than a guessed magnitude.
static func get_geometric_albedo(body: IVBody) -> float:
	var albedo_var: Variant = body.characteristics.get(&"albedo")
	if typeof(albedo_var) != TYPE_FLOAT:
		return 0.0
	var albedo: float = albedo_var
	return albedo


## Returns the (low, high) on-screen pixel radii of the disc/core crossfade for a
## source of [param magnitude_at_unit_distance] — the V magnitude it would have at a
## camera distance of 1.0 internal unit, holding phase and star distance fixed, so
## that [code]m(d) = magnitude_at_unit_distance + 5*log10(d)[/code].[br][br]
##
## [param can_crossfade] is true only for an EMISSIVE disc, which is already on the
## transparent pass and can alpha-fade; a lit body's surface must stay opaque or it stops
## writing depth, so its trade collapses to a step (see [constant HANDOFF_STEP_RATIO]).
## [br][br]
##
## [code]high[/code] is where the quad's saturated core matches the disc's diameter,
## i.e. where the two can trade places without stepping in size. Both are orders of
## magnitude above saturation throughout the handoff, so brightness is not what the
## eye has to go on — size is, and a crossfade that steps it reads as the abrupt
## shrink this ramp exists to prevent. Solving it also retires a hand-tuned constant
## that only ever suited one star at one [member IVPSFSettings.psf_sigma]: the
## answer moves with that roughly linearly (0.5 -> 3.8 px, 1.0 -> 7.8), so a literal
## would go stale the first time that shared slider moved.[br][br]
##
## Viewport-independence is what lets this live on the CPU at all, and it is not
## luck: hold the pixel radius fixed and a taller render puts the source
## proportionally farther, so the flux it loses to 1/d^2 is exactly what the shader's
## resolution law returns; fov cancels the same way against
## [member IVPSFSettings.fov_compensation]. Both cancellations are exact only at the
## calibrated [code]intensity_gamma[/code] 1.0 / [code]fov_compensation[/code] 1.0,
## which is why this evaluates at the reference height and fov; off-nominal it drifts
## a few percent, well inside the ~9% that star surface brightness moves the match
## across Proxima-to-Sirius-B anyway.
static func solve_handoff(magnitude_at_unit_distance: float, mean_radius: float,
		psf_settings: IVPSFSettings, can_crossfade: bool) -> Vector2:
	const ITERATIONS := 8 # p <- sigma*sqrt(2*ln I(p)) contracts by ~2*sigma^2/p^2 per step
	var high := HANDOFF_FALLBACK
	if is_finite(magnitude_at_unit_distance) and mean_radius > 0.0:
		var reference_height := get_reference_viewport_height()
		var reference_proj_11 := 1.0 / tan(deg_to_rad(psf_settings.fov_reference_deg) * 0.5)
		var distance_numerator := mean_radius * reference_proj_11 * reference_height * 0.5
		var pixels := 1.0
		for _iteration in ITERATIONS:
			var camera_distance := distance_numerator / pixels
			var apparent_magnitude := (magnitude_at_unit_distance
					+ FIVE_OVER_LN10 * log(camera_distance))
			var flux := 10.0 ** (-0.4 * (apparent_magnitude - psf_settings.intensity_faint_mag))
			var intensity := psf_settings.intensity_scale * flux ** psf_settings.intensity_gamma
			# Mirrors the shader chain, which multiplies iv_exposure unconditionally
			# (the static is 1.0 whenever physical light is inactive).
			intensity *= IVExposureManager.exposure
			if intensity <= 1.0:
				pixels = HANDOFF_FALLBACK # no saturated core to match; the disc is always bigger
				break
			pixels = psf_settings.psf_sigma * sqrt(2.0 * log(intensity))
		high = pixels
	var low_ratio := HANDOFF_LOW_RATIO if can_crossfade else HANDOFF_STEP_RATIO
	return Vector2(high * low_ratio, high)


## Returns the height the shaders' resolution law is normalized to, read from the
## setting the editor plugin writes from [code]ivoyager_core.cfg[/code] — the same
## one the shaders take as a global, so the two cannot disagree.
## [method RenderingServer.global_shader_parameter_get] would be the obvious reader
## and is a trap: it is editor-only, and in a running project it warns and hands back
## null rather than the value.
static func get_reference_viewport_height() -> float:
	const FALLBACK := 1080.0
	var setting: Variant = ProjectSettings.get_setting(
			"shader_globals/iv_reference_viewport_height")
	if setting is Dictionary:
		var setting_dict: Dictionary = setting
		var value: Variant = setting_dict.get("value")
		if value is float:
			return value
	push_warning("IVBodyPSF: no iv_reference_viewport_height shader global; using %s"
			% FALLBACK)
	return FALLBACK


func _init(body: IVBody) -> void:
	_body = body
	name = &"BodyPSF"
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	# Two triangles at the corners of a unit quad; body_psf.gdshader reads VERTEX.xy as
	# the corner sign and sizes the quad in pixels itself, so the mesh carries no scale.
	# farwarp is applied per-vertex in-shader, so the true-position AABB fails the frustum
	# test at exactly the distances this exists for -- size it to always contain the camera.
	var vertices := PackedVector3Array([
		Vector3(-1.0, -1.0, 0.0), Vector3(1.0, -1.0, 0.0), Vector3(1.0, 1.0, 0.0),
		Vector3(-1.0, -1.0, 0.0), Vector3(1.0, 1.0, 0.0), Vector3(-1.0, 1.0, 0.0),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var quad_mesh := ArrayMesh.new()
	quad_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var half_extent := IVCoreSettings.max_camera_distance
	quad_mesh.custom_aabb = AABB(-Vector3.ONE * half_extent, 2.0 * Vector3.ONE * half_extent)
	mesh = quad_mesh
	var shader: Shader = IVGlobal.resources[&"body_psf_shader"]
	_material = ShaderMaterial.new()
	_material.shader = shader
	material_override = _material


func _ready() -> void:
	_star = _body.star
	_is_sun = bool(_body.flags & BodyFlags.BODYFLAGS_STAR)
	# The quad's rim is drawn against the SILHOUETTE OF THE TABLE FIGURE (see get_limb_conic),
	# so it can only be drawn where that is the silhouette: the shared sphere, which the body
	# scales to its own radii. A body drawn with a mesh of its own outlines wherever its terrain
	# does -- 1.9 % of the radius inside the figure on Charon, 16 px on a 785 px disc -- and the
	# rim would stand off it as a detached arc of open sky. There is nothing here that could
	# find that outline, so such a body gets no rim (see RIM_SEAM_PX in the shader).
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	_draws_rim = (!_is_sun and !asset_preloader.get_body_packed_model(_body.name)
			and !asset_preloader.get_body_mesh(_body.name))
	_mean_radius = _body.mean_radius
	_equatorial_radius = _body.get_equatorial_radius()
	_polar_radius = _body.get_polar_radius()
	_geometric_albedo = 0.0 if _is_sun else get_geometric_albedo(_body)
	_color_bv = _body.characteristics.get(&"color_b_v", _color_bv)
	if _is_sun:
		_absolute_magnitude = _body.characteristics.get(&"absolute_magnitude", NAN)
	_lunar_lambert = _get_phase_blend()
	_material.set_shader_parameter(&"color_bv", _color_bv)
	# Past its handoff a source is a field star, so it images through the same camera the
	# field does -- one settings object, or the two drift apart on the first edit.
	_psf_settings = IVGlobal.program[&"PSFSettings"]
	_psf_settings.changed.connect(_on_psf_settings_changed)
	_psf_settings.apply_to(_material)


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if !viewport:
		return
	var camera := viewport.get_camera_3d()
	if !camera or !_star:
		return
	# True (un-farwarped) distance: this node sits at the body's true position (farwarp is a
	# per-vertex shader remap), so the body's own global_position gives the real distance.
	var camera_distance := _body.global_position.distance_to(camera.global_position)
	if camera_distance <= 0.0:
		return
	var apparent_magnitude := (_get_star_apparent_magnitude(camera_distance) if _is_sun
			else _get_reflected_apparent_magnitude(camera, camera_distance))
	# The size law is the only cutoff there is or should be -- it shrinks a source to nothing
	# exactly where it drops below one 8-bit step, and it runs in the shader because it is
	# viewport-dependent. So nothing here thresholds on brightness; this hides only where
	# there is no magnitude to draw at all (no albedo, degenerate geometry, an eclipse gone
	# total).
	if !is_finite(apparent_magnitude):
		visible = false
		return
	visible = true
	_refresh_handoff(apparent_magnitude, camera_distance)
	_material.set_shader_parameter(&"apparent_magnitude", apparent_magnitude)
	_material.set_shader_parameter(&"angular_radius", _mean_radius / camera_distance)
	_set_rim_parameters(camera)


# Re-solves the crossfade when the exposure or the source's distance-independent
# brightness has moved enough to shift it. Change-gated because the solve iterates;
# the NAN-initialized caches force the first frame. The published handoff is what the
# body's shells read to fade their disc, one frame later -- a lag on a smooth ramp,
# and the same convention every other per-frame publication here takes.
func _refresh_handoff(apparent_magnitude: float, camera_distance: float) -> void:
	# Distance-invariant by construction (a body that halves its distance brightens by
	# exactly 5*log10(2)), so this moves only with phase, heliocentric distance and eclipse.
	var unit_magnitude := apparent_magnitude - FIVE_OVER_LN10 * log(camera_distance)
	var exposure := IVExposureManager.exposure
	var exposure_ratio := exposure / _applied_exposure # NAN on first pass; comparisons false
	var magnitude_shift := absf(unit_magnitude - _applied_unit_magnitude)
	if (!is_nan(exposure_ratio) and !is_nan(magnitude_shift)
			and exposure_ratio < HANDOFF_REFRESH_RATIO
			and exposure_ratio > 1.0 / HANDOFF_REFRESH_RATIO
			and magnitude_shift < HANDOFF_REFRESH_RATIO - 1.0):
		return
	_applied_exposure = exposure
	_applied_unit_magnitude = unit_magnitude
	var handoff := solve_handoff(unit_magnitude, _mean_radius, _psf_settings, _is_sun)
	_material.set_shader_parameter(&"handoff_low", handoff.x)
	_material.set_shader_parameter(&"handoff_high", handoff.y)
	_body.psf_handoff = handoff


# The body's rim, as the quad's shader needs it: where the sun is on screen, at what phase,
# and the ellipse the body's silhouette actually is. The quad places its glare wing and draws
# the sky side of the rim's point spread from these (see body_psf.gdshader).
#
# The sun's screen direction falls to zero length as the sun goes directly behind or in front
# of the body, which is exactly where a lit side stops having a screen direction at all -- so
# both consumers collapse on their own there. A star gets a zero limb radius: it has no phase
# and no reflected rim, and its glare is its own.
#
# The apparent limb comes from the body's figure the way the analytic shadows take it
# (IVSunOcclusionManager, which treats the same bodies as oblate spheroids): the outline of a
# spheroid is an ellipse with the equatorial radius across the projected pole and
# sqrt(a^2 cos^2 + c^2 sin^2) along it, for the angle between the pole and the line of sight.
# A body whose real figure is a mesh gets no rim at all: the ellipse its table radii describe
# is not the outline the rasterizer draws, and the difference is percents of a radius rather
# than the fraction of a pixel RIM_SEAM_PX absorbs.
func _set_rim_parameters(camera: Camera3D) -> void:
	# The rim's geometry goes over in the camera's own frame, in units of the equatorial
	# radius (see get_limb_ellipsoid): the shader derives the phase angle and the sun's screen
	# direction from it, and the sun's angles at any limb point for the camera where it is.
	var camera_basis := camera.global_transform.basis
	var to_body := _body.global_position - camera.global_position
	var pole := _body.get_north_axis()
	var sun_direction := Vector3.ZERO
	if !_is_sun and _star:
		var star_vector := _star.global_position - _body.global_position
		if !star_vector.is_zero_approx():
			sun_direction = to_camera_frame(star_vector.normalized(), camera_basis)
	var radius_scale := 1.0 / _equatorial_radius if _equatorial_radius > 0.0 else 0.0
	var conic := get_limb_conic(to_body, pole, _equatorial_radius, _polar_radius, camera_basis)
	_material.set_shader_parameter(&"sun_direction", sun_direction)
	_material.set_shader_parameter(&"limb_camera_offset",
			to_camera_frame(-to_body, camera_basis) * radius_scale)
	_material.set_shader_parameter(&"limb_ellipsoid",
			get_limb_ellipsoid(pole, _equatorial_radius, _polar_radius, camera_basis))
	_material.set_shader_parameter(&"limb_conic", conic)
	_material.set_shader_parameter(&"limb_semi_axes",
			get_conic_semi_axes(conic) if _draws_rim else Vector2.ZERO)
	_material.set_shader_parameter(&"limb_centre_offset", get_conic_centre(conic).length())


## Returns the body's SILHOUETTE as a conic in the camera's tangent coordinates — screen
## offsets in units of tan(angle) from the body's own projected position, +Y up — so that
## [code][u v 1] C [u v 1]^T = 0[/code] is its limb. The quad's fragment solves that along
## its own direction for the radius it measures its distance beyond the limb from.[br][br]
##
## Exact for an oblate spheroid at any distance and orientation, which the rim needs and an
## angular radius cannot give: what a perspective projection draws is the TANGENT cone, wider
## than [code]r / d[/code] by 8 % at 2.6 radii out, and an oblate body's outline is an ellipse
## whose flattening is not the body's own. Both errors are tens of pixels on a body filling the
## screen, against a spread measured in single pixels — so the whole of it would land inside
## the silhouette and be culled. Tangent coordinates keep this viewport-independent (see the
## class note): the shader scales by its own focal length in pixels.[br][br]
##
## The derivation is the tangent cone of the quadric. For the ellipsoid [code]x^T A x = 1[/code]
## with the camera at [param P] (body-centred), a ray of direction [code]D[/code] is tangent
## where [code](P^T A D)^2 = (D^T A D)(P^T A P - 1)[/code]; writing D as the ray through screen
## offset (u, v) makes that a conic in (u, v). GLSL twin: none — the shader takes the answer.
static func get_limb_conic(to_body: Vector3, pole: Vector3, equatorial_radius: float,
		polar_radius: float, camera_basis: Basis) -> Basis:
	var forward := -camera_basis.z
	var depth := to_body.dot(forward)
	if depth <= 0.0 or equatorial_radius <= 0.0 or polar_radius <= 0.0:
		return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	# The ray through the body's own projected position, normalized to the tangent plane, so
	# that (u, v) are offsets from it rather than from the camera's axis.
	var centre_ray := to_body / depth
	var camera_offset := -to_body # camera, body-centred
	var inverse_equatorial_sq := 1.0 / (equatorial_radius * equatorial_radius)
	var pole_excess := 1.0 / (polar_radius * polar_radius) - inverse_equatorial_sq
	# A * v for the spheroid's quadric, without building the matrix.
	var a_right := camera_basis.x * inverse_equatorial_sq + pole * (pole_excess
			* camera_basis.x.dot(pole))
	var a_up := camera_basis.y * inverse_equatorial_sq + pole * (pole_excess
			* camera_basis.y.dot(pole))
	var a_centre := centre_ray * inverse_equatorial_sq + pole * (pole_excess
			* centre_ray.dot(pole))
	var a_camera := camera_offset * inverse_equatorial_sq + pole * (pole_excess
			* camera_offset.dot(pole))
	var outside := camera_offset.dot(a_camera) - 1.0 # > 0 with the camera outside the body
	var p_right := camera_offset.dot(a_right)
	var p_up := camera_offset.dot(a_up)
	var p_centre := camera_offset.dot(a_centre)
	var m_uu := outside * camera_basis.x.dot(a_right) - p_right * p_right
	var m_vv := outside * camera_basis.y.dot(a_up) - p_up * p_up
	var m_uv := outside * camera_basis.x.dot(a_up) - p_right * p_up
	var m_u1 := outside * centre_ray.dot(a_right) - p_centre * p_right
	var m_v1 := outside * centre_ray.dot(a_up) - p_centre * p_up
	var m_11 := outside * centre_ray.dot(a_centre) - p_centre * p_centre
	# A conic is defined up to scale, and this one is built from 1/radius^2 terms: Jupiter's
	# entries come out at 1e-15, whose 3x3 determinant is 1e-45 -- under float32's smallest
	# normal, so both Basis.determinant() here and the mat3 the shader solves would collapse to
	# zero. Normalizing costs nothing and puts every body's conic in the same numeric range.
	var largest := maxf(maxf(maxf(absf(m_uu), absf(m_vv)), maxf(absf(m_uv), absf(m_u1))),
			maxf(absf(m_v1), absf(m_11)))
	if largest <= 0.0:
		return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var normalize := 1.0 / largest
	m_uu *= normalize
	m_vv *= normalize
	m_uv *= normalize
	m_u1 *= normalize
	m_v1 *= normalize
	m_11 *= normalize
	return Basis(Vector3(m_uu, m_uv, m_u1), Vector3(m_uv, m_vv, m_v1), Vector3(m_u1, m_v1, m_11))


## Returns [param vector] in the camera's own frame — x right, y up, z FORWARD (the
## negative of the basis' z) — the frame the quad's rim uniforms share.
static func to_camera_frame(vector: Vector3, camera_basis: Basis) -> Vector3:
	return Vector3(vector.dot(camera_basis.x), vector.dot(camera_basis.y),
			-vector.dot(camera_basis.z))


## Returns the body's figure as the quadric [code]x^T E x = 1[/code], in the camera's frame
## (see [method to_camera_frame]) and in units of the equatorial radius so that its entries
## are of order one: the identity plus [code](a/c)^2 - 1[/code] times the pole's outer
## product. The quad's fragment takes the figure's normal at the point its limb ray touches:
## the sun's incidence THERE is what lights a rim, and from a camera at finite distance that
## point sees the sun lower than the body's centre does by the body's angular radius.
static func get_limb_ellipsoid(pole: Vector3, equatorial_radius: float, polar_radius: float,
		camera_basis: Basis) -> Basis:
	if equatorial_radius <= 0.0 or polar_radius <= 0.0:
		return Basis.IDENTITY
	var pole_excess := (equatorial_radius / polar_radius) ** 2 - 1.0
	var pole_camera := to_camera_frame(pole, camera_basis)
	var pole_outer := pole_excess * pole_camera
	return Basis(
			Vector3(1.0 + pole_outer.x * pole_camera.x, pole_outer.x * pole_camera.y,
					pole_outer.x * pole_camera.z),
			Vector3(pole_outer.y * pole_camera.x, 1.0 + pole_outer.y * pole_camera.y,
					pole_outer.y * pole_camera.z),
			Vector3(pole_outer.z * pole_camera.x, pole_outer.z * pole_camera.y,
					1.0 + pole_outer.z * pole_camera.z))


## Returns the centre, in tangent units, of the ellipse [method get_limb_conic]
## returns — which is NOT the body's own projected position: a sphere seen off the
## camera's axis has a silhouette offset outward from it, by 15 px here on a body
## filling a 4K frame. The quad is drawn on the body, so this is what its own extent
## has to carry beyond the ellipse's semi-axis.
static func get_conic_centre(conic: Basis) -> Vector2:
	var minor_determinant := conic.x.x * conic.y.y - conic.x.y * conic.x.y
	if minor_determinant == 0.0:
		return Vector2.ZERO
	return Vector2(conic.x.y * conic.y.z - conic.y.y * conic.x.z,
			conic.x.y * conic.x.z - conic.x.x * conic.y.z) / minor_determinant


## Returns the (major, minor) semi-axes, in tangent units, of the ellipse
## [method get_limb_conic] returns, or [constant Vector2.ZERO] if it is not one.
static func get_conic_semi_axes(conic: Basis) -> Vector2:
	var m_uu := conic.x.x
	var m_vv := conic.y.y
	var m_uv := conic.x.y
	var minor_determinant := m_uu * m_vv - m_uv * m_uv
	if minor_determinant <= 0.0:
		return Vector2.ZERO
	var offset_scale := -conic.determinant() / minor_determinant
	if offset_scale <= 0.0:
		return Vector2.ZERO
	var half_trace := 0.5 * (m_uu + m_vv)
	var spread := sqrt(maxf(half_trace * half_trace - minor_determinant, 0.0))
	var eigenvalue_low := half_trace - spread
	var eigenvalue_high := half_trace + spread
	if eigenvalue_low <= 0.0:
		return Vector2.ZERO
	return Vector2(sqrt(offset_scale / eigenvalue_low), sqrt(offset_scale / eigenvalue_high))


func _get_star_apparent_magnitude(camera_distance: float) -> float:
	if is_nan(_absolute_magnitude):
		return INF
	return IVPhotometry.get_apparent_magnitude(_absolute_magnitude, camera_distance)


# The whole disc's reflected flux as the magnitude an unresolved source of that flux
# would have. Phase, eclipse and both distances enter here; the albedo and the phase
# law are the body's own, so the point dims through phase exactly as the disc it
# hands off to (see IVPhotometry.get_disc_phase_function for what that costs).
func _get_reflected_apparent_magnitude(camera: Camera3D, camera_distance: float) -> float:
	var star_vector := _star.global_position - _body.global_position
	var star_distance := star_vector.length()
	if star_distance <= 0.0:
		return INF
	var star_absolute_magnitude: Variant = _star.characteristics.get(&"absolute_magnitude")
	if typeof(star_absolute_magnitude) != TYPE_FLOAT:
		return INF
	var star_magnitude: float = star_absolute_magnitude
	var star_illuminance := IVPhotometry.get_illuminance_from_apparent_magnitude(
			IVPhotometry.get_apparent_magnitude(star_magnitude, star_distance))
	star_illuminance *= IVSunOcclusionManager.get_parent_shadow_fraction(_body, _star,
			star_vector, star_distance)
	# camera -> body, matching the sign convention IVExposureManager meters with.
	var camera_vector := _body.global_position - camera.global_position
	var phase_cos := -star_vector.dot(camera_vector) / (star_distance * camera_distance)
	var phase_angle := acos(clampf(phase_cos, -1.0, 1.0))
	var phase_factor := IVPhotometry.get_disc_phase_function(phase_angle, _lunar_lambert)
	return IVPhotometry.get_reflected_apparent_magnitude(_geometric_albedo, _mean_radius,
			camera_distance, star_illuminance, phase_factor)


# The Lunar-Lambert L of the body's own surface shell, so the point's phase law is the
# law its disc renders with. A Minnaert deck (the giants, Venus, Titan) maps onto the
# same blend at both of its exact endpoints.
func _get_phase_blend() -> float:
	const DEFAULT_LUNAR_LAMBERT := 0.0 # Lambert, the surface shaders' own default
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	var overrides: Dictionary = asset_preloader.get_body_shell_specs(_body.name)[0][&"overrides"]
	var lunar_lambert_var: Variant = overrides.get(&"lunar_lambert")
	if typeof(lunar_lambert_var) == TYPE_FLOAT:
		var lunar_lambert: float = lunar_lambert_var
		return lunar_lambert
	var minnaert_var: Variant = overrides.get(&"minnaert_k")
	if typeof(minnaert_var) == TYPE_FLOAT:
		var minnaert_k: float = minnaert_var
		return IVPhotometry.get_minnaert_equivalent_lunar_lambert(minnaert_k)
	return DEFAULT_LUNAR_LAMBERT


func _on_psf_settings_changed() -> void:
	_psf_settings.apply_to(_material)
	_applied_exposure = NAN # the handoff moves with psf_sigma and the intensity chain
