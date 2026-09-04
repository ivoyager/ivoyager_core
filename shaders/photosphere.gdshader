// photosphere.gdshader
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
// unshaded: a star emits its own light and is never lit or self-shadowed (unlike the lit
// surface shader). skip_vertex_transform: for the farwarp vertex remap (see
// _farwarp.gdshaderinc). depth_draw_always: NOT the default, and load-bearing. Writing ALPHA
// puts this shader in the transparent pass, where the default depth_draw_opaque writes no
// depth at all -- occlusion then reduces to paint order, and anything at a higher
// render_priority draws straight through the star. Body name labels and symbols sit at
// IVBodyPositionVisual.HUD_RENDER_PRIORITY, so they labelled bodies that were behind the sun.
// The mode's cost would be the disc writing depth mid-crossfade and punching out the
// IVBodyPSF quad behind it; measured over the whole trade (0.4 to 40 AU, the handoff near
// 2-5 AU) it does not, the quad being the farther of two priority-0 transparent draws and so
// already painted when the disc lays its depth down.
render_mode unshaded, skip_vertex_transform, depth_draw_always;

// Near representation of an in-scene star ("sun"): the solid IVShellsModel surface
// (shell 0), rendered emissive. Set as the G_STAR surface class's "shader" column.
//
// The white-light photosphere -- limb darkening, granulation, bipolar sunspot groups and
// the intensity->color physics -- is wholly PROCEDURAL, pure functions on the unit-sphere
// direction: no map, no pole, no seam. That is the same textureless approach
// band_pattern.gdshader takes for the featureless banded bodies, and the Sun ships no
// surface map (the 2006 artist's texture is retired; see the assets build tree,
// records/Sun.md). Nothing here samples or discovers one, so a Sun.emission.* dropped into
// the assets tree is ignored, and a cubemap one draws IVShellsModel's "no cube variant"
// warning; a star that ever wants a map needs a shader of its own. The surface drives
// ALBEDO rather than EMISSION because "unshaded" outputs ALBEDO directly and ignores
// EMISSION. Farwarp keeps the disc's depth consistent with the warped orbit lines around
// it, exactly as the lit surface shader does.
//
// Two invariants the disc's calibration rests on:
//   - MEAN-NEUTRAL: every modulation is ~zero-mean over the disc (granulation by
//     construction, limb darkening by per-channel disc-average normalization), so the
//     disc keeps the calibrated mean surface brightness that IVShellsModel sun-mode
//     derives from the star's absolute magnitude, and the disc/point crossfade stays
//     photometric. Spots and faculae dent this by well under a percent, as real ones do.
//   - CHROMATICALLY NEUTRAL AT THE MEAN: photosphere_color(1.0) is exactly white, so
//     the star's absolute tint remains color_from_b_v(B-V)'s business and the disc matches
//     its PSF quad by construction. These functions carry only *relative* color:
//     umbrae redden as they darken, the limb reddens as it darkens.
//
// The photometric anchors, so the numbers are auditable:
//   - Limb darkening at 550 nm: I(mu)/I(1) = 0.30 + 0.93 mu - 0.23 mu^2 (Pierce &
//     Slaughter 1977, the standard quadratic; extreme limb 30 %, disc average 80.5 %).
//     R and B channels are constructed from that curve's shape with limb anchors 0.36
//     (610 nm) and 0.20 (465 nm), the Neckel & Labs center-to-limb trend -- the limb is
//     both darker and redder, ~1.7x R/B at the edge.
//   - Color: local intensity is read as a Planck-spectrum ratio at the channel
//     wavelengths (610/550/465 nm) against T0 = 5777 K (stars.tsv temp_photosphere).
//     Closed form, no LUT: an umbra at 0.15 of continuum lands at ~4100 K and renders
//     (0.180, 0.150, 0.107) -- the correct dark orange -- with no authored color anywhere.
//   - Granulation: ~1400 km cells (scale ~500 on the unit sphere), few-percent
//     contrast; supergranular mottling near 30 Mm at ~1 %. Static -- evolution is a
//     deliberate deferral, not an oversight (granule lifetime is ~10 min; a future
//     time input belongs on the sim clock).
//   - Spots: umbral intensity follows the brightness-size relation -- large umbrae
//     ~0.08 of continuum, small ~0.27, around the umbra_level=0.15 mid -- with
//     penumbra ~0.75 at 2.4x the umbral radius (photometric values, not styling;
//     an umbra is never truly black in radiance, ~4000 K, and photographs read
//     black only because the photosphere sets the exposure); log-distributed
//     umbral radii 0.004-0.016 of the solar radius; groups in activity belts
//     ~15 deg from the equator. Faculae brighten a ring zone around each group,
//     visible toward the limb (the real (1 - mu) behavior).
//
// Driven by IVShellsModel sun-mode, which sets "angular_radius" (the star's true angular
// size, radius/distance) each frame; this shader ramps the disc out against its own
// VIEWPORT_SIZE as the star shrinks toward a pixel and its IVBodyPSF quad takes over, so an
// off-screen capture fades at its own buffer's scale rather than the main window's.
// "brightness" is the star's HDR surface brightness (distance-invariant -- a resolved disc's
// surface brightness does not change with distance; only the point carries the distance
// gradient). No lighting, occlusion, or ring-shadow term -- the sun casts light, it does not
// receive it.
//
// Note the model's own "visible" is still culled against the main viewport by sun-mode: it is
// a node property and cannot resolve per viewport. See the sun-mode section of
// shells_model.gd for what that costs.

#include "_detail.gdshaderinc"          // hash, value_noise (the photosphere's noise)
#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_point_spread_function.gdshaderinc"


uniform float color_bv = 0.63;       // star B-V; tints the disc
uniform float color_saturation = 1.0; // shared with the field, so B-V reads the same either side
uniform float brightness = 1.0;      // HDR-capable surface-brightness multiplier (sun-mode sets)
uniform float angular_radius = 0.0;  // star radius / camera distance (sun-mode sets per frame)
uniform float handoff_low = -2.0;    // px on-screen radius at/below which the quad replaces this disc
uniform float handoff_high = -1.0;   // px at/above which this disc fully replaces the quad core (defaults saturate ON)
global uniform float iv_exposure;    // compensating-camera exposure; 1.0 when off (see stars.gdshader)

// Photosphere parameters (units and physics in the anchors above; scales are cells per
// radian of surface arc). Defaults are the Sun; shells.tsv columns of the same names can
// override per star if ever needed.
uniform float granulation_scale = 500.0;    // ~1400 km granules
uniform float granulation_contrast = 0.10;
uniform float mottle_scale = 45.0;          // supergranular mottling, ~30 Mm
uniform float mottle_contrast = 0.015;
uniform float spot_cell_scale = 6.0;        // spot-group spacing (cells per radian)
uniform float spot_activity = 0.12;         // in-belt spawn probability; 0 = spotless
uniform float spot_belt_center_deg = 15.0;  // butterfly-belt center latitude
uniform float spot_belt_width_deg = 9.0;
uniform float umbra_level = 0.15;           // continuum intensity in umbra / penumbra
uniform float penumbra_level = 0.75;
uniform float facula_contrast = 0.06;       // limb-side plage brightening around groups
uniform float spot_seed = 0.0;              // re-rolls the whole spot field

varying flat float v_alpha;
varying vec3 model_position;   // unit-sphere local position (captured before farwarp)
varying vec3 v_view_position;  // pre-farwarp view-space position, for the incidence cosine
varying vec3 v_view_normal;
varying flat float v_pixel_radius; // rendered px per radian of surface arc (alias fades)


// ----- limb darkening -----

// Quadratic coefficients (A, B, C) per channel: I(mu) = A + B mu + C mu^2, I(1) = 1.
const vec3 LIMB_A = vec3(0.36, 0.30, 0.20);
const vec3 LIMB_B = vec3(0.850285, 0.93, 1.062857);
const vec3 LIMB_C = vec3(-0.210285, -0.23, -0.262857);
// Disc average of each quadratic over the projected disc: A + 2B/3 + C/2. Dividing by
// it is what keeps the rendered disc at the calibrated MEAN surface brightness --
// center renders ~1.24x the mean, the limb ~0.37x, and the average is exactly 1.
const vec3 LIMB_DISC_MEAN = vec3(0.821714, 0.805, 0.777143);

// Per-channel I(mu) normalized to disc-average 1.0.
vec3 photosphere_limb_darkening(float mu) {
	return (LIMB_A + LIMB_B * mu + LIMB_C * mu * mu) / LIMB_DISC_MEAN;
}


// ----- intensity -> color physics -----

// exp(c2 / (lambda_c T0)) - 1 for 610/550/465 nm at T0 = 5777 K, and the wavelength
// ratios 550/610 and 550/465 that rescale the G channel's Planck exponent.
const float PLANCK_EXPM1_R = 58.317;
const float PLANCK_EXPM1_G = 91.601;
const float PLANCK_EXPM1_B = 210.884;
const float PLANCK_RATIO_R = 0.901639;
const float PLANCK_RATIO_B = 1.182796;

// Relative linear RGB of photosphere material whose 550 nm intensity is `intensity`
// (1.0 = mean photosphere -> exactly white). Solves the Planck spectrum ratio in
// closed form: intensity fixes ln-space temperature, R and B follow at their own
// wavelengths. Hotter is bluer, an umbra is its own correct orange.
vec3 photosphere_color(float intensity) {
	float lnterm = log(1.0 + PLANCK_EXPM1_G / max(intensity, 1e-4));
	float r = PLANCK_EXPM1_R / (exp(PLANCK_RATIO_R * lnterm) - 1.0);
	float b = PLANCK_EXPM1_B / (exp(PLANCK_RATIO_B * lnterm) - 1.0);
	return vec3(r, intensity, b);
}


// ----- granulation -----

// Zero-mean FBM with per-octave alias fade: each octave's amplitude ramps out as its
// lattice cell drops below ~2.5 rendered px, so the pattern never shimmers under
// camera motion at any zoom -- the procedural equivalent of a mip chain. px_per_cell
// is rendered px per cell of the FIRST octave (caller: disc px radius / scale).
float photosphere_fbm_faded(vec3 p, int octaves, float px_per_cell) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < octaves; octave++) {
		float fade = smoothstep(1.0, 2.5, px_per_cell);
		if (fade <= 0.0) {
			break; // finer octaves only get smaller
		}
		sum += amplitude * fade * (value_noise(p) - 0.5);
		p *= 2.0;
		amplitude *= 0.5;
		px_per_cell *= 0.5;
	}
	return sum;
}

// Granular cell field: |n1 + n2 - 1| puts its DARK values along the summed noise's
// median-crossing contours, which are connected -- dark intergranular lanes wrapping
// bright cell interiors, the actual convection morphology. (The other sign draws
// bright connected lines around dark blobs: inverted granulation. Measured previews
// caught exactly that.) TWO noise evaluations, the second in a rotated and rescaled
// domain, because one value noise's median contours hug its own lattice planes and
// the fold extracts them as rectangular corridors -- the grid-crease artifact
// _detail.gdshaderinc documents, at its worst. The sum's contours align to neither
// lattice. The 0.7 power narrows the lanes; faded FBM refines. Zero-mean: the
// field's mean under the summed bell distribution is measured by the build tree's
// shader mirror (scripts/sun_preview.py), not assumed.
const mat3 GRANULE_DOMAIN_ROT = mat3(
		vec3(0.628841, 0.729008, -0.270383),
		vec3(-0.581636, 0.671824, 0.458641),
		vec3(0.516003, -0.131148, 0.846488));
const float GRANULE_FIELD_MEAN = 0.3350;

float photosphere_granulation(vec3 dir, float scale, float px_per_cell) {
	float n1 = value_noise(dir * scale);
	float n2 = value_noise(GRANULE_DOMAIN_ROT * dir * (scale * 1.29));
	float field = pow(abs(n1 + n2 - 1.0), 0.7);
	float field_fade = smoothstep(1.0, 2.5, px_per_cell);
	float detail = photosphere_fbm_faded(dir * (scale * 2.0), 4, px_per_cell * 0.5);
	return field_fade * (field - GRANULE_FIELD_MEAN) + 0.8 * detail;
}


// ----- sunspots and faculae -----

// One spot's multiplicative intensity profile. The umbral and penumbral boundaries
// take SEPARATELY warped distances (d_umbra, d_penumbra): warped together the spot is
// just a scaled blobby circle, warped apart the umbra is its own irregular blob
// inside a raggedly-edged penumbra, which is the real morphology. depth_fade backs
// the whole spot off toward 1.0 when it is too small to render without aliasing.
// cell_umbra_level is this group's own umbral level, not the uniform: the
// brightness-size relation darkens a large umbra and lightens a small one.
float spot_profile(float d_umbra, float d_penumbra, float umbra_radius,
		float cell_umbra_level, float fluting, float depth_fade) {
	float penumbra_radius = 2.4 * umbra_radius;
	if (min(d_umbra, d_penumbra) >= penumbra_radius) {
		return 1.0;
	}
	float penumbra = mix(penumbra_level * (1.0 + fluting), 1.0,
			smoothstep(0.72 * penumbra_radius, penumbra_radius, d_penumbra));
	float level = mix(cell_umbra_level, penumbra,
			smoothstep(0.80 * umbra_radius, 1.20 * umbra_radius, d_umbra));
	return mix(1.0, level, depth_fade);
}

// A pore: a small penumbra-less dark dot, the other thing active regions carry.
float pore_profile(float d, float pore_radius, float depth_fade) {
	if (d >= 1.5 * pore_radius) {
		return 1.0;
	}
	float level = mix(0.4, 1.0, smoothstep(0.7 * pore_radius, 1.4 * pore_radius, d));
	return mix(1.0, level, depth_fade);
}

// The cell reach is a uniform, and never set: 1 is the 3x3x3 neighbourhood a jittered
// centre can land in. It is a uniform only so the GL compiler cannot unroll the 27 cells
// and inline a hash-drawn group into each; unrolled, this loop alone costs the sun shader
// 1 s to compile on the Compatibility renderer, opaque 0.4 s.
uniform int spot_cell_reach = 1;

// Sunspot groups from a 3D cell grid over the unit sphere. Each cell hashes a spawn
// decision gated by the butterfly-belt envelope at the CELL's latitude (never the
// fragment's, or spots would smear along parallels); a spawned cell projects a
// jittered center onto the sphere and composes a GROUP whose geometry is all
// hash-drawn, so no two look alike: single spot or bipolar pair (~35 % single),
// follower 0.45-0.85 of the leader, separation 2.5-6 umbral radii, the pair axis
// tilted from east-west by up to ~20 deg (leading spot equatorward, Joy's law), and
// up to two pores scattered through the group. Outlines are irregularized by the
// caller's two shared warp fields (warp_coarse lobes the umbrae -- a large spot
// spans several warp features and pinches toward multiple cores -- and with
// warp_fine ragged-edges the penumbrae). Two radial cell layers can both cut the
// shell and spawn close neighbors -- left in deliberately, real groups cluster.
// Returns the multiplicative intensity; facula_zone accumulates a ring-zone weight
// around each group for the caller's limb-dependent facular brightening.
//
// px_per_radian is the rendered px per radian of surface arc (the disc's px radius);
// it drives the per-spot alias fade.
float photosphere_spots(vec3 dir, float fluting, float warp_coarse, float warp_fine,
		float px_per_radian, out float facula_zone) {
	facula_zone = 0.0;
	vec3 base = floor(dir * spot_cell_scale);
	float shading = 1.0;
	float umbra_warp = 1.0 + 0.45 * warp_coarse;
	float penumbra_warp = 1.0 + 0.22 * warp_coarse + 0.18 * warp_fine;
	for (int i = -spot_cell_reach; i <= spot_cell_reach; i++) {
		for (int j = -spot_cell_reach; j <= spot_cell_reach; j++) {
			for (int k = -spot_cell_reach; k <= spot_cell_reach; k++) {
				vec3 cell = base + vec3(float(i), float(j), float(k));
				vec3 cell_center = (cell + 0.5) / spot_cell_scale;
				float radius = length(cell_center);
				// Only cells the unit-sphere shell actually cuts (half-diagonal margin).
				if (abs(radius - 1.0) * spot_cell_scale > 0.87) {
					continue;
				}
				float spawn = hash(cell + vec3(spot_seed, 71.7, -13.9));
				vec3 jitter = vec3(hash(cell + vec3(5.1, spot_seed, 27.3)),
						hash(cell + vec3(-31.7, 3.3, spot_seed)),
						hash(cell + vec3(spot_seed, -7.9, 57.1))) - 0.5;
				vec3 center = normalize(cell_center + jitter / spot_cell_scale);
				float lat_deg = degrees(asin(clamp(center.y, -1.0, 1.0)));
				float belt = exp(-pow((abs(lat_deg) - spot_belt_center_deg) / spot_belt_width_deg, 2.0));
				if (spawn > spot_activity * belt) {
					continue;
				}
				// Group geometry, all hash-drawn per cell.
				float size_hash = hash(cell + vec3(43.3, spot_seed, 11.1));
				float umbra_radius = 0.004 * pow(4.0, size_hash);
				// The umbral brightness-size relation: large umbrae are darker (V-band
				// core intensity ~0.05-0.10 of continuum for big spots, ~0.2-0.3 for
				// small ones). umbra_level is the mid-size value.
				float cell_umbra_level = umbra_level * mix(1.8, 0.55, size_hash);
				float follower_ratio = 0.45 + 0.4 * hash(cell + vec3(spot_seed, 33.9, 3.7));
				float separation = umbra_radius * (2.5 + 3.5
						* hash(cell + vec3(-3.1, 19.7, spot_seed)));
				float tilt = 0.55 * hash(cell + vec3(17.3, spot_seed, -41.1)) - 0.40;
				bool single = hash(cell + vec3(9.4, -55.2, spot_seed)) < 0.35;
				vec3 east = normalize(cross(vec3(0.0, 1.0, 0.0), center));
				vec3 north_t = cross(center, east);
				vec3 axis = normalize(east + tan(tilt) * north_t * sign(center.y));
				vec3 leader = normalize(center + axis * separation * 0.5);
				float depth_fade = smoothstep(0.7, 2.0, px_per_radian * umbra_radius);
				float d = distance(dir, leader);
				shading *= spot_profile(d * umbra_warp, d * penumbra_warp, umbra_radius,
						cell_umbra_level, fluting, depth_fade);
				if (!single) {
					vec3 follower = normalize(center - axis * separation * 0.5);
					d = distance(dir, follower);
					shading *= spot_profile(d * umbra_warp, d * penumbra_warp,
							follower_ratio * umbra_radius, cell_umbra_level, fluting, depth_fade);
				}
				// Up to two pores scattered through the group.
				float pore_hash = hash(cell + vec3(-27.9, 61.3, spot_seed));
				if (pore_hash > 0.3) {
					vec3 pore = normalize(center + (axis * (pore_hash - 0.65)
							+ north_t * (hash(cell + vec3(51.7, spot_seed, 23.9)) - 0.5))
							* separation * 1.2);
					d = distance(dir, pore) * (1.0 + 0.45 * warp_fine);
					shading *= pore_profile(d, 0.22 * umbra_radius, depth_fade);
				}
				if (pore_hash > 0.6) {
					vec3 pore = normalize(center + (axis * (1.15 - pore_hash)
							+ north_t * (hash(cell + vec3(-15.3, spot_seed, 47.1)) - 0.5))
							* separation * 1.4);
					d = distance(dir, pore) * (1.0 + 0.45 * warp_coarse);
					shading *= pore_profile(d, 0.30 * umbra_radius, depth_fade);
				}
				// Facular ring zone around the group.
				float group_d = distance(dir, center);
				float zone_radius = 2.4 * umbra_radius * 1.7;
				facula_zone += depth_fade * max(0.0,
						1.0 - abs(group_d - zone_radius) / (1.3 * zone_radius));
			}
		}
	}
	return shading;
}


// ----- assembled surface -----

// The full scalar intensity field at unit direction `dir` seen at incidence cosine
// `mu`, at `px_per_radian` rendered px per radian of surface arc. 1.0-mean by the
// invariants above; feed it to photosphere_color() and multiply by
// photosphere_limb_darkening(mu).
float photosphere_intensity(vec3 dir, float mu, float px_per_radian) {
	float granulation = photosphere_granulation(dir, granulation_scale,
			px_per_radian / granulation_scale);
	float mottle = photosphere_fbm_faded(dir * mottle_scale, 3, px_per_radian / mottle_scale);
	float intensity = 1.0 + granulation_contrast * granulation + mottle_contrast * mottle;
	// Penumbral texture rides a finer, weaker noise than the granulation cells: strong
	// coarse modulation reads as a moth-eaten penumbra (measured preview), not filaments.
	float fluting = 0.5 * photosphere_fbm_faded(dir * (granulation_scale * 3.0), 2,
			px_per_radian / (granulation_scale * 3.0));
	// Two shared spot-outline warp fields (~centered, +-1, alias-faded): coarse lobes
	// the umbrae, fine ragged-edges penumbrae and pores. Shared across every spot --
	// each intersects its own region of the fields, so shapes differ anyway.
	float warp_coarse = 4.0 * photosphere_fbm_faded(dir * 180.0, 1, px_per_radian / 180.0);
	float warp_fine = 4.0 * photosphere_fbm_faded(dir * 420.0, 1, px_per_radian / 420.0);
	float facula_zone;
	intensity *= photosphere_spots(dir, fluting, warp_coarse, warp_fine, px_per_radian,
			facula_zone);
	// Faculae: bright toward the limb, invisible at disc center, as real plage is.
	intensity *= 1.0 + facula_contrast * min(facula_zone, 1.5) * (1.0 - mu);
	return intensity;
}


void vertex() {
	model_position = VERTEX;
	vec3 view_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_view_position = view_position;
	// A unit sphere's normal is its own local position.
	v_view_normal = MODELVIEW_NORMAL_MATRIX * VERTEX;
	VERTEX = farwarp(view_position);
	float pixel_radius = body_pixel_radius(angular_radius, PROJECTION_MATRIX[1][1], VIEWPORT_SIZE.y);
	v_pixel_radius = pixel_radius;
	v_alpha = body_disc_weight(pixel_radius, handoff_low, handoff_high);
}

void fragment() {
	// Drop a fully-faded disc here rather than through a CPU "visible" flag: this resolves per
	// viewport, where a node property could only ever answer for the viewport its node lives in.
	// Under depth_draw_always it is also what stops a handed-off disc from writing depth over
	// the IVBodyPSF quad that has replaced it.
	if (v_alpha <= 0.0) {
		discard;
	}
	// mu is computed per fragment, not per vertex: the limb-darkening curve is steepest
	// exactly where mu -> 0, and per-vertex interpolation would band the limb on the
	// shared sphere mesh's tessellation.
	float mu = clamp(dot(normalize(-v_view_position), normalize(v_view_normal)), 0.0, 1.0);
	vec3 dir = normalize(model_position);
	float intensity = photosphere_intensity(dir, mu, v_pixel_radius);
	vec3 surface = photosphere_color(intensity) * photosphere_limb_darkening(mu);
	// The photometric scalar caps at the point's shared f16-safe ceiling: under physical
	// light, brightness carries the star's true surface brightness (~1e11 in rendered
	// units), which nothing meters down while the star is a minor part of the frame, and
	// an inf in the f16 buffer would poison downstream passes. Capping the scalar (not
	// the channels) keeps surface contrast and B-V hue wherever f16 can represent
	// the value, exactly as psf_core_light_sprite does for the far point.
	float disc_light = min(brightness * iv_exposure, PSF_LIGHT_MAX);
	// Nothing sampled this radiance, so no renderer decode cancels against it: it crosses
	// into the renderer's own colour space here (see _display.gdshaderinc).
	ALBEDO = display_write(surface * color_from_b_v(color_bv, color_saturation) * disc_light);
	ALPHA = v_alpha;
}
