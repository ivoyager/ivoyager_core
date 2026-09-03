// _sun_photosphere.gdshaderinc
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

// Procedural white-light photosphere for the sun_surface shader pair: limb darkening,
// granulation, bipolar sunspot groups and the intensity->color physics, all as pure
// functions on the unit-sphere direction -- no map, no pole, no seam. Replaces the
// retired artist's texture (see the assets build tree, records/Sun.md). Requires
// _detail.gdshaderinc included first (hash, value_noise).
//
// Two invariants the callers rely on:
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
float spot_profile(float d_umbra, float d_penumbra, float umbra_radius, float umbra_level,
		float penumbra_level, float fluting, float depth_fade) {
	float penumbra_radius = 2.4 * umbra_radius;
	if (min(d_umbra, d_penumbra) >= penumbra_radius) {
		return 1.0;
	}
	float penumbra = mix(penumbra_level * (1.0 + fluting), 1.0,
			smoothstep(0.72 * penumbra_radius, penumbra_radius, d_penumbra));
	float level = mix(umbra_level, penumbra,
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
// it drives the per-spot alias fade. seed varies the whole field.
float photosphere_spots(vec3 dir, float cell_scale, float activity, float belt_center_deg,
		float belt_width_deg, float umbra_level, float penumbra_level, float fluting,
		float warp_coarse, float warp_fine, float px_per_radian, float seed,
		out float facula_zone) {
	facula_zone = 0.0;
	vec3 base = floor(dir * cell_scale);
	float shading = 1.0;
	float umbra_warp = 1.0 + 0.45 * warp_coarse;
	float penumbra_warp = 1.0 + 0.22 * warp_coarse + 0.18 * warp_fine;
	for (int i = -spot_cell_reach; i <= spot_cell_reach; i++) {
		for (int j = -spot_cell_reach; j <= spot_cell_reach; j++) {
			for (int k = -spot_cell_reach; k <= spot_cell_reach; k++) {
				vec3 cell = base + vec3(float(i), float(j), float(k));
				vec3 cell_center = (cell + 0.5) / cell_scale;
				float radius = length(cell_center);
				// Only cells the unit-sphere shell actually cuts (half-diagonal margin).
				if (abs(radius - 1.0) * cell_scale > 0.87) {
					continue;
				}
				float spawn = hash(cell + vec3(seed, 71.7, -13.9));
				vec3 jitter = vec3(hash(cell + vec3(5.1, seed, 27.3)),
						hash(cell + vec3(-31.7, 3.3, seed)),
						hash(cell + vec3(seed, -7.9, 57.1))) - 0.5;
				vec3 center = normalize(cell_center + jitter / cell_scale);
				float lat_deg = degrees(asin(clamp(center.y, -1.0, 1.0)));
				float belt = exp(-pow((abs(lat_deg) - belt_center_deg) / belt_width_deg, 2.0));
				if (spawn > activity * belt) {
					continue;
				}
				// Group geometry, all hash-drawn per cell.
				float size_hash = hash(cell + vec3(43.3, seed, 11.1));
				float umbra_radius = 0.004 * pow(4.0, size_hash);
				// The umbral brightness-size relation: large umbrae are darker (V-band
				// core intensity ~0.05-0.10 of continuum for big spots, ~0.2-0.3 for
				// small ones). umbra_level is the mid-size value.
				float cell_umbra_level = umbra_level * mix(1.8, 0.55, size_hash);
				float follower_ratio = 0.45 + 0.4 * hash(cell + vec3(seed, 33.9, 3.7));
				float separation = umbra_radius * (2.5 + 3.5
						* hash(cell + vec3(-3.1, 19.7, seed)));
				float tilt = 0.55 * hash(cell + vec3(17.3, seed, -41.1)) - 0.40;
				bool single = hash(cell + vec3(9.4, -55.2, seed)) < 0.35;
				vec3 east = normalize(cross(vec3(0.0, 1.0, 0.0), center));
				vec3 north_t = cross(center, east);
				vec3 axis = normalize(east + tan(tilt) * north_t * sign(center.y));
				vec3 leader = normalize(center + axis * separation * 0.5);
				float depth_fade = smoothstep(0.7, 2.0, px_per_radian * umbra_radius);
				float d = distance(dir, leader);
				shading *= spot_profile(d * umbra_warp, d * penumbra_warp, umbra_radius,
						cell_umbra_level, penumbra_level, fluting, depth_fade);
				if (!single) {
					vec3 follower = normalize(center - axis * separation * 0.5);
					d = distance(dir, follower);
					shading *= spot_profile(d * umbra_warp, d * penumbra_warp,
							follower_ratio * umbra_radius, cell_umbra_level,
							penumbra_level, fluting, depth_fade);
				}
				// Up to two pores scattered through the group.
				float pore_hash = hash(cell + vec3(-27.9, 61.3, seed));
				if (pore_hash > 0.3) {
					vec3 pore = normalize(center + (axis * (pore_hash - 0.65)
							+ north_t * (hash(cell + vec3(51.7, seed, 23.9)) - 0.5))
							* separation * 1.2);
					d = distance(dir, pore) * (1.0 + 0.45 * warp_fine);
					shading *= pore_profile(d, 0.22 * umbra_radius, depth_fade);
				}
				if (pore_hash > 0.6) {
					vec3 pore = normalize(center + (axis * (1.15 - pore_hash)
							+ north_t * (hash(cell + vec3(-15.3, seed, 47.1)) - 0.5))
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
float photosphere_intensity(vec3 dir, float mu, float granulation_scale,
		float granulation_contrast, float mottle_scale, float mottle_contrast,
		float spot_cell_scale, float spot_activity, float spot_belt_center_deg,
		float spot_belt_width_deg, float umbra_level, float penumbra_level,
		float facula_contrast, float spot_seed, float px_per_radian) {
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
	intensity *= photosphere_spots(dir, spot_cell_scale, spot_activity, spot_belt_center_deg,
			spot_belt_width_deg, umbra_level, penumbra_level, fluting, warp_coarse,
			warp_fine, px_per_radian, spot_seed, facula_zone);
	// Faculae: bright toward the limb, invisible at disc center, as real plage is.
	intensity *= 1.0 + facula_contrast * min(facula_zone, 1.5) * (1.0 - mu);
	return intensity;
}
