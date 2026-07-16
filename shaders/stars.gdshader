// stars.gdshader
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

// Point-sprite star field for IVStarsVisual. Each vertex is a star at its true
// ecliptic position (internal units); CUSTOM0 carries raw (V magnitude, B-V).
// The per-vertex farwarp remap (shared with the small-body points and orbit
// lines) pulls distant stars inside the camera far plane while preserving screen
// direction, so stars render behind everything at any zoom. depth_draw_never +
// blend_add means opaque bodies occlude stars (depth test stays on) but stars
// never occlude each other and sum like real light.
//
// The target is a good camera's image of the sky, not a photon count and not the naked
// eye: a bright star is a saturated core inside a soft halo. That is modelled directly.
// Every star shares one point-spread function of fixed width psf_sigma, and only its
// intensity varies -- exactly as a camera behaves, where one optical PSF images every
// star and a brighter one merely pushes more of that PSF above the sensor's saturation.
//
// This is what sizes stars, and nothing else does. A star's visible radius is where its
// PSF falls to one 8-bit step, sigma*sqrt(2*ln(255*I)), so apparent size grows as
// sqrt(ln(intensity)): unbounded in principle, flat in practice (480x the brightness is
// ~1.5x the radius). That is a soft size limit with no clamp anywhere -- a clamp would
// flatten the bright end into a set of identical stars, which is the one thing a star
// field must never look like.
//
// POINT_SIZE is therefore only a bounding box: it is set to that visible radius, so the
// round mask cuts exactly where the star reaches 1/255 and a hard edge cannot appear at
// any brightness. Do not tie the falloff to it. An earlier version did (the Gaussian's
// width was a fixed fraction of POINT_SIZE), which made a bright star a scaled-up copy of
// a faint one instead of a brighter one, and left its whole footprint -- including the
// 1.8%-of-peak rim -- far above saturation. Every bright star was then a flat white disc
// with a knife edge, which is precisely the phony look this shape exists to avoid.
//
// intensity is HDR and deliberately unclamped: with no glow pass it clips to white in the
// framebuffer, and a future glow pass will bloom it in proportion to true brightness.
// Intensity and color convert from raw magnitude/B-V here (not baked), keeping the door
// open for a physical-light pass.
//
// intensity_gamma compresses flux before the PSF sees it, and is calibrated to 1.0 -- none.
// Photometry of the NASA starmap_2020 reference (its stars matched against the Hipparcos
// catalog, aperture flux vs V magnitude) puts its unsaturated faint end at -0.44 mag^-1
// where the photometric law is -0.40: linear. The reference's bright/dim compression is
// saturation of its own source imagery, not a curve -- the same mechanism modelled here.
// Below 1.0 the field is compressed a second time on top of saturation, flattening it
// toward uniform blobs. The other uniforms are still by eye; the structure is the durable
// part.
//
// Nothing floors the sprite size and nothing needs to. The size law welds size to
// brightness: inverted, a star's peak is exp(size^2/(8*sigma^2)) 8-bit steps, so at sigma
// 0.5 a 1 px star peaks at 1.6/255 and a 3 px star at 90/255. A bright pin-point cannot
// exist here, so the sub-pixel blinking a floor would guard against (point sampling below
// the Nyquist limit) can only happen where the star is already invisible.
//
// The background panorama holds constant on-screen brightness across fov -- it is
// surface-brightness-conserving, sampled per pixel. Fixed-size star sprites do not:
// as fov narrows the field thins (fewer stars, each unchanged), so stars fade
// against a magnified nebula when zooming in and swamp it when zooming out.
// reference_tan_half_fov / fov_compensation scale each star by the inverse pixel
// solid angle (1/tan^2(fov/2)), holding the field's total luminance fov-invariant to
// match the background. PROJECTION_MATRIX supplies the live fov, so it tracks zoom.
//
// Resolution is the other half of that pixel solid angle ((2*tan(fov/2)/height)^2), and it
// takes the same fix as fov: scale intensity, hold the PSF. psf_sigma is the sensor's
// sharpness, in absolute pixels, at every resolution -- so a taller render resolves finer
// angular detail and the stars stay pin-sharp, which is the whole point of rendering at 4K.
// Scaling the PSF with the frame instead would make a 4K render a blurrier rendition of the
// 1080p picture rather than a better one: same stars, twice as fuzzy, nothing gained. The
// PSF belongs to the camera, not to the picture.
//
// Intensity carries the invariance instead, by (height/reference)^2. Total light per star
// goes as intensity*sigma^2, so that holds each star's share of the frame fixed against the
// per-pixel background while its footprint stays put. The sqrt(ln) size law makes this
// nearly free: 4x the intensity widens a faint star by ~13% (3.1 -> 3.5 px), and the rest
// shows up as a slightly wider saturated core -- which is what a better sensor looks like.

uniform float psf_sigma = 0.5; // px at any resolution; the camera PSF that images every star
uniform float intensity_faint_mag = 6.5; // magnitude at the intensity floor
uniform float intensity_gamma = 1.0; // flux compression; 1.0 = photometric, as calibrated (see header)
uniform float intensity_scale = 0.5; // linear intensity at intensity_faint_mag
uniform float color_saturation = 1.0; // 0 = white field; 1 = the physical B-V color (see star_color)

// Resolution compensation (see header). A very bright star in a tall render could still
// reach a platform's ALIASED_POINT_SIZE_RANGE clamp, but the sqrt(ln) size law makes that
// far harder to hit than a linear ramp did; 20 px is known good on tested platforms, and
// anything above that is untested and accepted as a platform risk.
// The reference height is a global (see ivoyager_core.cfg): the sun's point shares it, and
// two visuals compensating against two references would drift apart.
global uniform float iv_reference_viewport_height;

// Field-of-view brightness compensation (see header): keeps the field's on-screen
// luminance constant across zoom so stars track the background.
uniform float reference_tan_half_fov = 0.4663; // tan(fov/2) where compensation is 1.0 (fov 50 deg)
uniform float fov_compensation = 1.0; // 0 = off (fixed brightness); 1 = full 1/tan^2(fov/2) law

varying flat float v_bv;
varying flat float v_intensity;
varying flat float v_falloff;

#include "_farwarp.gdshaderinc"
#include "_star_point.gdshaderinc"


void vertex() {
	v_bv = CUSTOM0.y;
	vec3 view_position = farwarp((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	POSITION = PROJECTION_MATRIX * vec4(view_position, 1.0);
	// Unclamped: the bright end must stay distinguishable, and the size law compresses it
	// (see header). Both compensations belong here rather than in the fragment, because a
	// star brightened by a zoom or a taller render must saturate a correspondingly wider
	// core -- they are what a longer exposure does, not a post-hoc gain on the pixels.
	float flux = star_flux(CUSTOM0.x, intensity_faint_mag);
	float resolution_scale = VIEWPORT_SIZE.y / iv_reference_viewport_height;
	float intensity = intensity_scale * pow(flux, intensity_gamma)
			* star_fov_compensation(PROJECTION_MATRIX[1][1], reference_tan_half_fov,
			fov_compensation)
			* resolution_scale * resolution_scale;
	v_intensity = intensity;
	POINT_SIZE = star_visible_size(intensity, psf_sigma);
	v_falloff = star_psf_falloff(POINT_SIZE, psf_sigma);
}


void fragment() {
	float dist_sq = star_point_dist_sq(POINT_COORD); // 0 at center, 1 at the inscribed circle
	if (dist_sq > 1.0) {
		discard; // round mask; drops the square point-sprite corners
	}
	// The PSF multiplies in-shader rather than via ALPHA so it sees full precision
	// before the f16 buffer write; see star_point_light.
	ALBEDO = star_color(v_bv, color_saturation) * star_point_light(v_intensity, dist_sq, v_falloff);
	ALPHA = 1.0; // blend_add: the add is ALBEDO * ALPHA, already folded above
}
