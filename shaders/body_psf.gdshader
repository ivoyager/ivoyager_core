// body_psf.gdshader
// This file is part of I, Voyager
// https://ivoyager.dev
// *****************************************************************************
// Copyright 2019-2026 Charlie Whitfield
// I, Voyager is a registered trademark of Charlie Whitfield in the US
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// *****************************************************************************
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, blend_add, depth_draw_never;

// The camera's point-spread response to one body's flux: the Gaussian PSF core, the r^-2
// glare wing, and the sky side of the body's own rim, on a camera-facing quad. Driven by IVBodyPSF, which sets the apparent
// magnitude and angular radius from true (un-farwarped) geometry each frame -- for an
// in-scene star from its own luminosity, for a sunlit body from its albedo, phase and the
// two distances. The law is the catalog star field's, shared function for function through
// _point_spread_function.gdshaderinc, which is what welds an in-scene source to the sky
// behind it: this fragment should read as stars.gdshader's sibling, because it is one.
//
// THE TWO REGIMES. Unresolved, this quad IS the body: the core takes the disc handoff
// (angular_radius -> pixel radius -> the crossfade the surface shader fades out on), so a
// body that shrinks past its disc becomes a photometric point rather than vanishing at a
// distance cull. Resolved, the WING persists -- glare belongs to the camera and not to the
// subject, so it takes no crossfade -- and that persisting wing is the crescent glow.
//
// THE RIM'S SKY SIDE, and why it can only be drawn here. A body's surface shader images each
// rim pixel through the camera's PSF, but it can only put that light on fragments the body
// has: its rim ends at the rasterized silhouette, and the outward half of a rim pixel's point
// spread belongs beyond it. Left undrawn, a rim compressed to a line keeps a knife edge, which
// on a shallow curve is a staircase -- an atmosphere has none because its shell stands off the
// surface and its ring reconstructs across the edge. This quad already covers the sky beside
// the limb, so the missing half is drawn here: the same closed-form chord integral under the
// same Gaussian (limb_sky_side_incidence(), the sibling of the surface's limb_mean_incidence()),
// evaluated outward from the limb, scaled so the two halves partition one convolution. What it
// integrates is the sun's height above the LIMB's horizon for the camera where it is
// (limb_sun_angles()), not the phase at the body's centre: from three radii out the two differ
// by the body's 18 deg angular radius, and the surface this has to meet has the real normal.
//
// It is the body's OWN flux that scales it -- the magnitude the core would draw, spread over a
// Lambert sphere's disc -- rather than anything sampled from the surface, which this quad has
// no access to. So the total is the body's true flux through its true phase law, while the
// distribution across the crescent is Lambert's. What that costs is the seam: a body whose rim
// albedo differs from its disc average meets its own spread at a slightly different level.
//
// WHY ONE ITEM RATHER THAN TWO. This merges what were sun_point.gdshader (a point sprite)
// and sun_glare.gdshader (a quad). Two draws are two adds in the blend, and on the
// display-referred renderer a blend runs on ENCODED values, where a sum is not a sum. Core
// and wing are therefore summed in linear here and cross into the renderer's colour space
// through one display_write(), exactly as the field's own fragment does. One item is also
// one farwarped position, one uniform set, and one place for what used to be a discipline
// note ("must track stars.gdshader uniform for uniform").
//
// WHY A QUAD. POINT_SIZE's driver maximum is 64 in the Vulkan spec's floor and as little as
// 1 in the GLES3 spec's -- and the web export is GLES3 -- while the glare law runs to ~700 px
// for the sun seen from Earth. A quad has no cap. (The field keeps sprites and accepts the
// clamp as a stated risk: it can only truncate a wing's faint outer part.)
//
// Rendered on a 6-vertex unit quad parented to the body's IVBody, so it sits at the true
// position and rides the origin shift; the per-vertex farwarp remap (shared with the field)
// keeps it inside the camera far plane at any distance. blend_add + depth_draw_never with the
// depth test left on: an opaque body in front cuts it where it covers it, it never occludes
// anything, and it sums like light.
//
// KNOWN ARTIFACT, and why the final write stays in one place. Over a bright background -- the
// Milky Way's bulge -- blend_add on the display-referred renderer lands enc(g) where the
// linear sum wants enc(bg + g) - enc(bg), several-fold at the wing's faint end, so the halo
// reads ~2-3x wider there than over dark sky. (Forward+ adds in linear.) The exact fix is a
// screen-texture increment -- sample hint_screen_texture, write enc(dec(S) + g) - S under the
// same blend_add -- at the cost of one backbuffer copy per frame while a quad is visible.
// Not implemented; the fragment's one final write is kept in one place so it can slot in.

#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_photometry.gdshaderinc"
#include "_point_spread_function.gdshaderinc"

// The field's photometry, shared value for value with stars.gdshader through IVStarSettings,
// which owns the uniform names. These defaults must track that shader's; nothing enforces it,
// and any drift shows up as an in-scene source disagreeing with the stars around it.
uniform float psf_sigma = 0.5;
uniform float intensity_faint_mag = 6.5;
uniform float intensity_gamma = 1.0;
uniform float intensity_scale = 0.5;
uniform float color_saturation = 1.0;
uniform float glare_scale = 0.0126;
uniform float glare_gamma = 0.286;
uniform float glare_max_px = 384.0;
global uniform float iv_reference_viewport_height;
uniform float reference_tan_half_fov = 0.4663;
uniform float fov_compensation = 1.0;
global uniform float iv_exposure; // a global, so this cannot drift from the field

// Per-body, set each frame by IVBodyPSF. Both are viewport-independent: this shader
// resolves them against its own VIEWPORT_SIZE and PROJECTION_MATRIX, so an off-screen
// capture is sized for its own buffer rather than for the main window.
uniform float apparent_magnitude = -20.0; // V magnitude at the current distance and phase
uniform float color_bv = 0.63;            // B-V -> source color, through the field's ramp
uniform float angular_radius = 0.0;       // body radius / camera distance; the LOD ramp's input
uniform float handoff_low = 1.0;          // px radius at/below which this fully replaces the disc
uniform float handoff_high = 2.5;         // px at/above which the disc fully replaces this core

// THE BODY'S RIM, as this quad needs it; IVBodyPSF sets all six each frame.
//
// The first three are in the camera's own frame (right, up, forward), in units of the body's
// equatorial radius: the sun's direction, the camera's position from the body's centre, and the
// body's figure as the quadric x^T E x = 1. Together they give the sun's angles at any point of
// the limb for the camera where it IS (limb_sun_angles), and the phase angle and sun's screen
// direction the wing takes. The silhouette arrives as the CONIC it actually is
// (IVBodyPSF.get_limb_conic), in tangent units this shader scales by its own focal length: the
// fragment solves it along its own direction rather than comparing against a radius. An angular
// radius could not do it -- perspective draws the tangent cone, 8 % wider than r/d at 2.6 radii
// out, and an oblate body's outline is an ellipse -- and both errors are tens of pixels where
// the spread being drawn is a few. Two cases both mean "no rim to draw here": sun_direction is
// zero for an emissive body, which has no lit side, and limb_semi_axes is zero for a star and
// for a body whose FIGURE IS NOT THIS ELLIPSE -- one drawn with its own mesh, whose real outline
// stands wherever its terrain does (see RIM_SEAM_PX).
uniform vec3 sun_direction = vec3(0.0);  // unit, camera frame; zero for a star
uniform vec3 limb_camera_offset = vec3(0.0, 0.0, -1.0); // the camera from the body's centre
uniform mat3 limb_ellipsoid;      // the body's figure, x^T E x = 1, same frame and units
uniform mat3 limb_conic;          // the silhouette, in tangent coordinates (+Y up)
uniform vec2 limb_semi_axes = vec2(0.0); // its (major, minor) semi-axes, same units
uniform float limb_centre_offset = 0.0; // and how far its centre sits from the body's

// How far inside the analytic limb the sky-side spread still draws, in px. The ellipse above is
// the body's figure while the silhouette on screen is a tessellated sphere just inside it, so
// the two edges disagree by a fraction of a pixel; holding the spread at its limb value across
// that closes the seam, and the disc's own fragments are in front of this quad and drop it
// anyway. It absorbs a TESSELLATION error and nothing else. A body carrying its own mesh
// departs from its table figure by percents of its radius rather than by a pixel -- measured
// on Charon at 1.9 %, which is 16 px on a 785 px disc -- and no constant here could reach that:
// the rim drew as an arc of open sky, detached from the terrain it belonged to. Such a body
// gets limb_semi_axes zero from IVBodyPSF and no rim at all.
const float RIM_SEAM_PX = 1.0;

varying flat float v_intensity; // core intensity, crossfade already folded in
varying flat float v_glare;     // wing amplitude at 1 px
varying flat float v_radius;    // the quad's half-width in px
varying flat vec2 v_wing_centre; // the wing's centre, px from the quad's centre
varying flat float v_focal_px;  // px per tangent unit, for the limb conic
varying flat float v_rim_amplitude; // the lit limb's flux density, per unit incidence
varying flat float v_rim_reach; // how far out the sky-side spread is worth drawing, px
varying flat vec2 v_rim_band;   // the px radii the sky-side spread can fall between
varying vec2 v_offset;          // this vertex's corner, in [-1, 1]


// Where a ray from the body's projected position along a screen direction (+Y up) crosses the
// silhouette, in tangent units: the conic restricted to that ray is a quadratic in the
// distance, and the body's centre is inside its own outline, so the two roots straddle zero and
// the positive one is the limb. Zero where the conic is degenerate.
float limb_tangent_along(vec2 direction_up) {
	// The ray's third component is zero and the body's own position is the origin, so the
	// quadratic's coefficients come straight out of the conic's 2x2 block and its last column
	// -- no mat3 product, on a function every fragment of the rim band calls.
	vec3 conic_last = limb_conic[2];
	float ray_term = dot(direction_up, mat2(limb_conic[0].xy, limb_conic[1].xy) * direction_up);
	float cross_term = 2.0 * dot(conic_last.xy, direction_up);
	float discriminant = cross_term * cross_term - 4.0 * ray_term * conic_last.z;
	if (discriminant <= 0.0 || ray_term == 0.0) {
		return 0.0;
	}
	// The two roots straddle zero, so the limb is the larger: written as centre plus half-span
	// to spend one divide rather than two.
	float half_reciprocal = 0.5 / ray_term;
	return -cross_term * half_reciprocal + abs(sqrt(discriminant) * half_reciprocal);
}

// The sun's angles AT THE POINT OF THE LIMB this screen direction touches -- along the view and
// along the outward normal, the pair limb_sky_side_incidence() takes -- for the camera where it
// is. A camera at finite distance sees the TANGENT circle, and a point on it sees the sun lower
// than the body's centre does by the body's angular radius: 18 deg from three radii out. Lit
// from the centre's phase angle instead, this rim stood as if the sun were that far above a
// limb it was sitting on, stayed lit after the sun had set behind the disc, and went out only
// at phase 180 -- while the surface, which has the real normal, had gone dark with the sun. The
// ray through the silhouette at tangent offset limb_tangent touches the figure at the double
// root of its quadric, and the figure's normal there is E times the touching point.
vec2 limb_sun_angles(vec2 direction_up, float limb_tangent) {
	vec3 centre_ray = limb_camera_offset / limb_camera_offset.z;
	vec3 limb_ray = centre_ray + vec3(direction_up * limb_tangent, 0.0);
	vec3 figure_ray = limb_ellipsoid * limb_ray;
	float touch = -dot(limb_camera_offset, figure_ray) / dot(limb_ray, figure_ray);
	vec3 normal = normalize(limb_ellipsoid * (limb_camera_offset + touch * limb_ray));
	return vec2(-dot(normalize(limb_ray), sun_direction), dot(normal, sun_direction));
}

void vertex() {
	// VERTEX.xy carries the corner sign; the mesh is a unit quad and the size is set here.
	v_offset = VERTEX.xy;
	// The body itself sits at the mesh origin. Project THAT, then push the corner out in
	// clip space, so the quad is camera-facing and sized in pixels at any orientation.
	vec3 view_position = farwarp((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	vec4 center = PROJECTION_MATRIX * vec4(view_position, 1.0);
	// Unclamped, and both compensations belong here rather than in the fragment: a source
	// brightened by a zoom or a taller render must saturate a correspondingly wider core --
	// that is what a longer exposure does, not a post-hoc gain on the pixels.
	float flux = flux_from_magnitude(apparent_magnitude, intensity_faint_mag);
	float resolution_scale = VIEWPORT_SIZE.y / iv_reference_viewport_height;
	float intensity = intensity_scale * pow(flux, intensity_gamma)
			* point_fov_compensation(PROJECTION_MATRIX[1][1], reference_tan_half_fov,
			fov_compensation)
			* resolution_scale * resolution_scale * iv_exposure;
	// The crossfade scales the core's intensity, so a partly-faded core is photometrically
	// just a fainter source -- size and peak stay welded by the size law at every fade level,
	// and no special case or size floor is needed. The WING takes the full intensity: it does
	// not fade, because the crossfade decides whether the camera RESOLVES the body and glare
	// is the imaging system's, not the subject's. A resolved body glares harder, not less.
	float pixel_radius = body_pixel_radius(angular_radius, PROJECTION_MATRIX[1][1],
			VIEWPORT_SIZE.y);
	v_intensity = intensity * (1.0 - body_disc_weight(pixel_radius, handoff_low,
			handoff_high));
	// Both screen directions arrive in the camera's own terms (+Y up) while the corner offsets
	// below are clip space, whose +Y points DOWN under Vulkan and up under GL. Unsigned they land
	// mirrored across the body on one renderer of the two -- a second light on the dark limb.
	vec2 screen_to_clip = vec2(1.0, sign(PROJECTION_MATRIX[1][1]));
	float sun_screen_length = length(sun_direction.xy);
	vec2 sun_up = sun_screen_length > 0.0 ? sun_direction.xy / sun_screen_length : vec2(0.0);
	vec2 sun_clip = sun_up * screen_to_clip;
	v_focal_px = abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y * 0.5;
	// cos of the phase angle at the body's centre, +1 at full and -1 at new: what the wing's
	// offset and the disc integral want, and NOT what lights the limb (see limb_sun_angles).
	float phase_cos = dot(normalize(limb_camera_offset), sun_direction);
	// Where the silhouette stands in the sun's own screen direction. Everything the crescent
	// does happens at or inside this: it is the lit limb's place, and the far end of the disc
	// the wing must stay on.
	float limb_sun_tangent = limb_tangent_along(sun_up);
	float limb_sun_px = limb_sun_tangent * v_focal_px;
	// Lambert's disc integral of mu0, in units of the disc's area: what the body's flux is
	// spread over, and the distant observer's phase law itself.
	float phase = acos(clamp(phase_cos, -1.0, 1.0));
	float disc_integral = (2.0 / 3.0) * (sin(phase) + (PI - phase) * phase_cos);
	// THE FLUX THIS CAMERA RECEIVES, against the flux a distant one would. The magnitude driving
	// this quad carries the body's phase law evaluated at the body's CENTRE, which is a distant
	// observer's crescent: from close range the camera sees less than a hemisphere, so the sun
	// sets behind the disc while that law still reports a crescent -- at Saturn from 3.7 radii
	// the whole visible face is dark past 164 deg of phase, where the law still says 4e-4 of
	// full. Every limb point sees the sun at sin(phase + rho) for the silhouette's own angular
	// radius rho, so a distant observer with that much more phase has this camera's geometry:
	// the substitution is exact where the crescent dies and where the body is far (rho -> 0),
	// and within a third of a magnitude between, which on a glare halo is nothing.
	float visible_phase = min(phase + atan(limb_sun_tangent), PI);
	float visible_integral = (2.0 / 3.0) * (sin(visible_phase)
			+ (PI - visible_phase) * cos(visible_phase));
	float visible_flux_ratio = disc_integral > 0.0
			? max(visible_integral, 0.0) / disc_integral : 1.0;
	// ONLY THE WING TAKES IT. The core is a point source only where the body is unresolved, and
	// there the two fluxes agree exactly. The rim divides the same flux by the same disc
	// integral, so the correction cancels out of it -- which is right: a crescent's surface
	// brightness is its albedo and its illuminance, and does not care how much of it is left.
	// The wing is the one term that stands outside the silhouette, glaring for the whole body.
	v_glare = psf_glare_amplitude(intensity * visible_flux_ratio, glare_scale, glare_gamma,
			glare_max_px * resolution_scale);
	// A CRESCENT'S LIGHT IS NOT CENTRED ON THE BODY, and while the wing was, the glare sat
	// symmetrically around a disc whose lit part was a sliver off to one side. Offsetting it by
	// a phase-dependent fraction of the SILHOUETTE'S radius in that direction puts that spill
	// where the light actually is, and keeps the r^-2 singularity on the disc, which draws over
	// it. A fraction of the mean radius does not: a mean lies BETWEEN an oblate body's polar and
	// equatorial extents, so past Saturn's pole the centre stood 10 px out in open sky, where an
	// exposed r^-2 peak is a dot with a glow around it. The core does NOT take the offset:
	// unresolved, the quad IS the body, and the body is where it is. The silhouette radius
	// retires the offset as the disc shrinks toward that regime, as a pixel radius did. The
	// FRACTION is by eye -- a Lambert sphere's lit centroid is at 4/(3*PI) of the radius at
	// quarter phase against this curve's 0.5, and closing that gap would mean carrying the disc
	// integral of whichever BRDF the body renders with.
	v_wing_centre = sun_clip * ((1.0 - phase_cos) * 0.5) * limb_sun_px;
	// THE RIM'S SKY SIDE (see the header). Amplitude first: the body's whole flux is
	// intensity * 2*PI*sigma^2 -- what its Gaussian core integrates to -- and a Lambert sphere
	// spreads that over its projected disc as flux/(area * J) per unit mu0, with J the disc
	// integral of mu0 in units of the disc's area. The apparent ellipse carries the area term,
	// so an oblate body's rim is not brightened by the polar radius it does not have. The
	// crossfade is the disc's, not the core's: the spread belongs to a body being RESOLVED, and
	// it retires exactly as the core takes over, leaving the point source undisturbed.
	// The quad is drawn on the BODY, and a silhouette seen off the camera's axis is centred
	// away from it, so its far side reaches the semi-axis plus that offset. Sizing to the
	// semi-axis alone cost the rim wherever the offset pointed: the round mask cut the limb,
	// and with it every fragment the spread had to be drawn on.
	float limb_major_px = (limb_semi_axes.x + limb_centre_offset) * v_focal_px;
	float limb_minor_px = (limb_semi_axes.y - limb_centre_offset) * v_focal_px;
	float limb_area_px = limb_semi_axes.x * limb_semi_axes.y * v_focal_px * v_focal_px;
	// The sun's angles at the limb point nearest it, where the spread is brightest: the sun
	// below that point's horizon is below every limb point's, and there is no rim at all.
	vec2 sun_angles_peak = limb_sun_angles(sun_up, limb_sun_tangent);
	v_rim_amplitude = 0.0;
	v_rim_reach = 0.0;
	if (limb_area_px > 0.0 && disc_integral > 0.0 && limb_sun_tangent > 0.0
			&& sun_angles_peak.y > 0.0) {
		v_rim_amplitude = intensity * TAU * psf_sigma * psf_sigma
				* body_disc_weight(pixel_radius, handoff_low, handoff_high)
				/ (limb_area_px * disc_integral);
		// Reach by the same size law the core and the field's stars take, evaluated on the
		// brightest place the spread has: the lit limb, where its own Gaussian starts.
		float limb_peak = v_rim_amplitude * limb_sky_side_incidence(sun_angles_peak.x,
				sun_angles_peak.y, 0.0, limb_sun_px, psf_sigma);
		v_rim_reach = 0.5 * psf_visible_size(limb_peak, psf_sigma);
	}
	// The band the silhouette can fall in, from the ellipse's own extremes: no fragment outside
	// it has a rim, whatever direction it lies in. The disc's interior is most of a resolved
	// body's quad, and this is what keeps the conic solve off it.
	v_rim_band = vec2(limb_minor_px - RIM_SEAM_PX, limb_major_px + v_rim_reach);
	// The quad must span whichever component reaches further. psf_visible_size returns a
	// DIAMETER and psf_glare_draw_size a RADIUS, so the core halves and the wing does not.
	// The wing's reach is measured from its own offset centre, so that distance is added --
	// without it the quad would clip the wing on the lit side, which is the side it moved to.
	// The rim's is measured from the limb, so the silhouette's own radius is added to it.
	v_radius = max(0.5 * psf_visible_size(v_intensity, psf_sigma),
			max(psf_glare_draw_size(v_glare) + length(v_wing_centre),
			limb_major_px + v_rim_reach));
	// One NDC unit is half the viewport, and the corner offset is in clip units, so it
	// scales by w. Behind the camera (w <= 0) that scaling flips the corners and would draw
	// the quad mirrored across the frame instead of not at all -- farwarp keeps the body
	// inside the FAR plane and says nothing about the near one -- so every corner goes
	// outside the guard band and the triangles clip away. Written as a branch on POSITION
	// rather than an early exit: Godot's shader language rejects a return in vertex().
	vec2 ndc_radius = 2.0 * v_radius / VIEWPORT_SIZE;
	if (center.w > 0.0) {
		POSITION = vec4(center.xy + v_offset * ndc_radius * center.w, center.zw);
	} else {
		POSITION = vec4(2.0, 2.0, 1.0, 1.0);
	}
}


void fragment() {
	float radius_px = length(v_offset) * v_radius;
	if (radius_px > v_radius) {
		discard; // round mask; drops the square quad's corners
	}
	// Core plus wing, summed in linear before the one conversion, so the pair crosses into
	// the renderer's colour space as one value rather than as two adds in the blend (see
	// header). Both multiply here rather than via ALPHA so they see full precision before the
	// f16 buffer write; see psf_core_light_sprite. Nothing sampled this radiance, so no renderer
	// decode cancels against it: it crosses over here (see _display.gdshaderinc).
	// The core is measured from the body, the wing from where the lit light actually is.
	vec2 offset_px = v_offset * v_radius;
	float wing_px = length(offset_px - v_wing_centre);
	// The rim's sky-side spread, on the band just beyond the silhouette. The disc's own
	// fragments are inside the branch's reach test and skip the kernel: the depth test drops
	// them, but a shader with a discard in it cannot be trusted to be rejected before it runs.
	float rim = 0.0;
	if (v_rim_amplitude > 0.0 && radius_px > max(v_rim_band.x, 0.0) && radius_px < v_rim_band.y) {
		vec2 direction_up = (offset_px / radius_px) * vec2(1.0, sign(PROJECTION_MATRIX[1][1]));
		float limb_tangent = limb_tangent_along(direction_up);
		float limb_px = limb_tangent * v_focal_px;
		float distance_px = radius_px - limb_px;
		if (limb_tangent > 0.0 && distance_px > -RIM_SEAM_PX && distance_px < v_rim_reach) {
			vec2 sun_angles = limb_sun_angles(direction_up, limb_tangent);
			rim = min(v_rim_amplitude * limb_sky_side_incidence(sun_angles.x, sun_angles.y,
					max(distance_px, 0.0), limb_px, psf_sigma), PSF_LIGHT_MAX);
		}
	}
	float light = psf_core_light(v_intensity, radius_px, psf_sigma)
			+ psf_glare_light(v_glare, wing_px) + rim;
	ALBEDO = display_write(color_from_b_v(color_bv, color_saturation) * light);
	ALPHA = 1.0; // blend_add: the add is ALBEDO * ALPHA, already folded above
}
