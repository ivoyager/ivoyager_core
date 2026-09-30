// _atmosphere.min.gdshaderinc
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

// The Min tier's integration of a view ray. _atmosphere.gdshaderinc includes this file in place
// of its quadrature where a shader has defined ATM_MIN (THE MIN VARIANT in that file's header);
// never include it on its own. It supplies the two functions the shared entry points call,
// atm_disc() and atm_ring_pixel(), and nothing else differs: the model, its columns, the receiver
// light and the entry points are the full tier's, so a surface's own colour is the full tier's
// exactly and only the air in front of it and beyond the limb is approximated.
//
// Each segment of a ray -- the lit part in front of a disc, the far half of an optical limb's
// tangent ray, either half of a beyond-limb ray -- is integrated in closed form from its columns
// at a few points. The model, its assumptions and what they cost on screen are under *The Min
// tier* in *Atmospheres* in PHOTOMETRIC_MODEL.md.
//
// THE STRUCTURE (the including file's header) is relaxed here, and measured: atm_min_point() is
// reached from one call site per segment kind, which in the limb shader is two, and a Min program
// still compiles faster than its full counterpart through FXC (*The atmosphere's structure* in
// GRAPHICS_PROFILING.md).

// Trip counts, uniforms for the reason atm_ray_segments is; nothing sets them.
uniform int atm_min_disc_points = 5;
uniform int atm_min_tangent_points = 3;

// The share of a tangent half-ray's column between its tangent point (altitude h) and distance u
// along it, for an exponential of scale height H.
float atm_min_half_fraction(float R, float h, float u, float H) {
	float r_t = R + h;
	float dz = u * u / (sqrt(r_t * r_t + u * u) + r_t);
	return atm_erf(sqrt(max(dz, 0.0) / H));
}

// The columns at one point of a view ray, at altitude z: `view`, the ray's column above the point
// (its zenith cosine there mu_v, its tangent altitude h_ray); `source`, what each layer's share of
// that column scatters toward the camera per unit optical depth, summed; and `sun`, the sun's
// column along mu_s. The gas and haze parts of the view and sun columns come out separately too,
// for the stacked limit (atm_stacking).
void atm_min_point(AtmLayers L, float R, float z, float mu_v, float mu_s, float h_ray,
		float gas_source, out vec3 view, out vec3 source, out vec3 sun, out vec3 gas_view,
		out vec3 haze_view, out vec3 gas_sun, out vec3 haze_sun) {
	gas_view = vec3(0.0);
	haze_view = vec3(0.0);
	gas_sun = vec3(0.0);
	haze_sun = vec3(0.0);
	for (int ray = 0; ray < atm_node_rays; ray++) {
		vec3 gas;
		vec3 haze;
		atm_exp_columns(L, R, z, ray == 0 ? mu_v : mu_s, true, gas, haze);
		if (ray == 0) {
			gas_view = gas;
			haze_view = haze;
		} else {
			gas_sun = gas;
			haze_sun = haze;
		}
	}
	sun = gas_sun + haze_sun;
	view = gas_view + haze_view;
	source = gas_source * gas_view + L.scatter_h * haze_view;
	if (L.has_layer) {
		vec3 above;
		vec3 sun_column;
		atm_shell_node_columns(L, R, z, h_ray, mu_s, above, sun_column);
		view += above;
		source += L.scatter_l * above;
		sun += sun_column;
	}
}

// A column integrated along a segment on which the exponent runs piecewise linearly through
// (t_top, e_top), (t_mid, e_mid), (t_bottom, e_bottom), t the column from the camera: the integral
// of e^-E over the column, per channel.
vec3 atm_min_piecewise(vec3 t_top, vec3 e_top, vec3 t_mid, vec3 e_mid, vec3 t_bottom,
		vec3 e_bottom) {
	return max(t_mid - t_top, vec3(0.0)) * atm_exp_mean(e_top, e_mid)
			+ max(t_bottom - t_mid, vec3(0.0)) * atm_exp_mean(e_mid, e_bottom);
}

// Surface-hit ray at a point with view cosine mu and sun cosine mu0 (sz = dot(e, s) as for the
// ring): the path radiance of its lit part and -- where the disc is an optical limb -- of the far
// half of its tangent ray beyond, and the view transmittance of what lies beneath. The full tier's
// atm_disc(), in closed form.
void atm_disc(AtmLayers L, float R, float mu, float mu0, float sz, float sun_ang,
		float far_floor, out vec3 path, out vec3 transmittance) {
	path = vec3(0.0);
	float gas_source = atm_gas_multiple * atm_phase_rayleigh(-sz);
	float root = sqrt(max(1.0 - mu * mu, 0.0));
	float b_ray = R * root;
	float h_v = -R * mu * mu / (1.0 + root);
	// The ray's lit part in front of the disc, as atm_ray_path() finds it.
	vec2 lit = atm_lit_interval(R, R * R * (1.0 - mu0 * mu0), R * mu0, sz,
			R * (mu - mu0 * sz), max(1.0 - sz * sz, 1.0e-12));
	float u_lo = lit.x;
	float u_hi = min(lit.y, 1.0e9);
	bool disc_open = lit.y >= ATM_INF;
	float z_lit = sqrt(R * R + 2.0 * R * mu * u_lo + u_lo * u_lo) - R;
	float z_cap = disc_open ? ATM_INF : sqrt(R * R + 2.0 * R * mu * u_hi + u_hi * u_hi) - R;
	bool near_on = z_lit < 46.0 * L.H_ref && z_cap > z_lit;
	// Where the sun is low along the lit part, or the part is capped or starts above the disc, the
	// sun's column does not fall with the view column's, and a second anchor, one upper scale
	// height along, measures how it runs.
	bool gas_upper_disc;
	float stacked_disc = atm_stacking(L, L.H_h, gas_upper_disc);
	float H_upper = gas_upper_disc ? L.H_g : L.H_h;
	float mu_s_lit = (R * mu0 + u_lo * sz) / (R + z_lit);
	bool drift_on = near_on && (mu_s_lit < 0.25 || !disc_open || z_lit > 0.0);
	float z_a = min(z_lit + H_upper, disc_open ? ATM_INF : 0.5 * (z_lit + z_cap));
	// The far half of the ray's tangent ray, where atm_ray_path() takes it: from where it is lit,
	// floored at the disc, outward.
	bool far_on = h_v > far_floor;
	float qs_far = clamp(R * (mu0 - mu * sz) / max(b_ray, 1.0e-3), -1.0, 1.0);
	float half_a = b_ray * qs_far;
	float r_t = R + h_v;
	float z_far = 0.0;
	if (far_on) {
		float b = -sz;
		vec2 far_lit = atm_lit_interval(R, b_ray * b_ray * (1.0 - qs_far * qs_far), half_a, b,
				-half_a * b, max(1.0 - b * b, 1.0e-12));
		float far_lo = far_lit.x;
		z_far = max(h_v + far_lo * far_lo / (sqrt(r_t * r_t + far_lo * far_lo) + r_t), 0.0);
		float far_hi = min(far_lit.y, 1.0e9);
		float z_far_hi = far_lit.y >= ATM_INF ? ATM_INF
				: h_v + far_hi * far_hi / (sqrt(r_t * r_t + far_hi * far_hi) + r_t);
		far_on = z_far < 46.0 * L.H_ref && z_far_hi > z_far;
	}
	// The columns at five points: the near part's lit start and its cap, the tangent point (the
	// whole ray), the far half's lit start, and the second anchor. One loop, one atm_min_point().
	vec3 near_view = vec3(0.0);
	vec3 near_source = vec3(0.0);
	vec3 near_sun = vec3(0.0);
	vec3 cap_view = vec3(0.0);
	vec3 near_gas_v = vec3(0.0);
	vec3 near_haze_v = vec3(0.0);
	vec3 near_gas_s = vec3(0.0);
	vec3 near_haze_s = vec3(0.0);
	vec3 cap_gas_v = vec3(0.0);
	vec3 cap_haze_v = vec3(0.0);
	vec3 up_view = vec3(0.0);
	vec3 up_sun = vec3(0.0);
	vec3 up_gas_v = vec3(0.0);
	vec3 up_haze_v = vec3(0.0);
	vec3 up_gas_s = vec3(0.0);
	vec3 up_haze_s = vec3(0.0);
	vec3 total = vec3(0.0);
	vec3 far_view = vec3(0.0);
	vec3 far_source = vec3(0.0);
	vec3 far_sun = vec3(0.0);
	for (int point = 0; point < atm_min_disc_points; point++) {
		bool wanted = point < 2 ? near_on && (point == 0 || !disc_open)
				: (point < 4 ? far_on : drift_on);
		if (!wanted) {
			continue;
		}
		float z = h_v;
		float mu_v = 0.0;
		float mu_s = qs_far;
		if (point < 2 || point == 4) {
			z = point == 0 ? z_lit : (point == 1 ? z_cap : z_a);
			float u = point == 0 ? u_lo : (point == 1 ? u_hi : atm_chord(R, z_a, h_v) - R * mu);
			mu_v = (R * mu + u) / (R + z);
			mu_s = (R * mu0 + u * sz) / (R + z);
		} else if (point == 3) {
			float u = atm_chord(R, z_far, h_v);
			z = z_far;
			mu_v = u / (R + z);
			mu_s = (half_a - u * sz) / (R + z);
		}
		vec3 view;
		vec3 source;
		vec3 sun;
		vec3 gas_v;
		vec3 haze_v;
		vec3 gas_s;
		vec3 haze_s;
		atm_min_point(L, R, z, mu_v, mu_s, h_v, gas_source, view, source, sun, gas_v, haze_v,
				gas_s, haze_s);
		if (point == 0) {
			near_view = view;
			near_source = source;
			near_sun = sun;
			near_gas_v = gas_v;
			near_haze_v = haze_v;
			near_gas_s = gas_s;
			near_haze_s = haze_s;
		} else if (point == 1) {
			cap_view = view;
			cap_gas_v = gas_v;
			cap_haze_v = haze_v;
		} else if (point == 2) {
			total = 2.0 * view;
		} else if (point == 4) {
			up_view = view;
			up_sun = sun;
			up_gas_v = gas_v;
			up_haze_v = haze_v;
			up_gas_s = gas_s;
			up_haze_s = haze_s;
		} else {
			far_view = view;
			far_source = source;
			far_sun = sun;
		}
	}
	if (near_on) {
		// Without the second anchor its point is the lit start's, and each piecewise run below
		// reduces to the plain k-form: the exponent (1 + k) T, k = sun / view there.
		if (!drift_on) {
			up_view = near_view;
			up_sun = near_sun;
			up_gas_v = near_gas_v;
			up_haze_v = near_haze_v;
			up_gas_s = near_gas_s;
			up_haze_s = near_haze_s;
		}
		// Past the second anchor toward the camera the sun keeps the ratio it has there.
		vec3 k_up = 1.0 + up_sun / max(up_view, vec3(1.0e-12));
		vec3 near_path = atm_min_piecewise(cap_view, cap_view * k_up, up_view, up_view + up_sun,
				near_view, near_view + near_sun) * near_source / max(near_view, vec3(1.0e-12));
		bool gas_upper = gas_upper_disc;
		float stacked = stacked_disc;
		if (stacked > 0.0) {
			// STACKED: each exponential layer's run with only its own column, the lower one's light
			// crossing the whole of the upper as well.
			vec3 gas_k = 1.0 + up_gas_s / max(up_gas_v, vec3(1.0e-12));
			vec3 haze_k = 1.0 + up_haze_s / max(up_haze_v, vec3(1.0e-12));
			vec3 gas_self = atm_min_piecewise(cap_gas_v, cap_gas_v * gas_k, up_gas_v,
					up_gas_v + up_gas_s, near_gas_v, near_gas_v + near_gas_s);
			vec3 haze_self = atm_min_piecewise(cap_haze_v, cap_haze_v * haze_k, up_haze_v,
					up_haze_v + up_haze_s, near_haze_v, near_haze_v + near_haze_s);
			vec3 stacked_path = gas_source * gas_self
					* (gas_upper ? vec3(1.0) : exp(-near_haze_v - near_haze_s))
					+ L.scatter_h * haze_self * (gas_upper ? exp(-near_gas_v - near_gas_s) : vec3(1.0));
			near_path = mix(near_path, stacked_path, stacked);
		}
		path += near_path;
	}
	if (far_on) {
		// Outward from the far lit start the exponent runs from the rest of the ray plus the sun's
		// column there, to the whole ray.
		path += far_source * atm_exp_mean(total - far_view + far_sun, total);
	}
	// What the disc beneath keeps, delta-scaled, as the full tier's atm_disc() has it.
	vec3 view_total = atm_exp_column_beneath(L, R, 0.0, mu);
	if (L.has_layer) {
		view_total += atm_shell_partial(L, R, 0.0, h_v) * L.delta_l;
	}
	transmittance = exp(-view_total);
	// The full tier's finite guard, for its reason (see its atm_disc()).
	if (any(isnan(path)) || any(isinf(path))) {
		path = vec3(0.0);
	}
	if (any(isnan(transmittance)) || any(isinf(transmittance))) {
		transmittance = vec3(1.0);
	}
}

// A beyond-limb ray tangent at altitude h (qs the sun's cosine at the tangent point, sz its
// component along the ray toward the camera): the radiance of both halves' lit parts, and the
// transmittance of what lies behind the ray.
vec3 atm_min_tangent(AtmLayers L, float R, float h, float qs, float sz, float sun_ang,
		out vec3 tangent_transmittance) {
	float gas_source = atm_gas_multiple * atm_phase_rayleigh(-sz);
	float r_t = R + h;
	float half_a = r_t * qs;
	float half_p0_perp2 = r_t * r_t * (1.0 - qs * qs);
	vec3 total = vec3(0.0);
	vec3 per_depth = vec3(0.0); // the ray's radiance per unit of its optical depth
	vec3 gas_half = vec3(0.0);
	vec3 haze_half = vec3(0.0);
	float H_haze = L.z_k > 0.0 && h > L.z_k ? L.H_t : L.H_h;
	bool gas_upper;
	float stacked = atm_stacking(L, H_haze, gas_upper);
	vec3 path = vec3(0.0);
	// Point 0 is the tangent point, for the whole ray's columns; 1 and 2 are where each half's
	// sun column is held.
	for (int point = 0; point < atm_min_tangent_points; point++) {
		float z = h;
		float mu_v = 0.0;
		float mu_s = qs;
		vec3 t_a = vec3(0.0);
		vec3 t_b = vec3(0.0);
		vec3 onion = vec3(0.0);
		float sign_s = point == 1 ? 1.0 : -1.0; // +1 the camera's side
		if (point > 0) {
			// The half's lit part, and the view column from the camera at its two ends: a half
			// holds half the ray's column, spread from the tangent point as erf(sqrt(dz / H)).
			float b = sign_s * sz;
			vec2 lit = atm_lit_interval(R, half_p0_perp2, half_a, b, -half_a * b,
					max(1.0 - b * b, 1.0e-12));
			float f_lo = atm_min_half_fraction(R, h, lit.x, L.H_ref);
			float f_hi = lit.y >= ATM_INF ? 1.0
					: atm_min_half_fraction(R, h, min(lit.y, 1.0e9), L.H_ref);
			if (f_hi <= f_lo) {
				continue;
			}
			vec3 half_column = 0.5 * total;
			t_a = half_column * (point == 1 ? 1.0 - f_hi : 1.0 + f_lo);
			t_b = half_column * (point == 1 ? 1.0 - f_lo : 1.0 + f_hi);
			if (stacked > 0.0) {
				// STACKED: the lower layer is the ray's core. On the near half the upper layer's lit
				// part stands in front of it; on the far half the whole near half does, core included.
				bool near = point == 1;
				float lit_hi = min(lit.y, 1.0e9);
				bool open = lit.y >= ATM_INF;
				float gas_lo = atm_min_half_fraction(R, h, lit.x, L.H_g);
				float gas_hi = open ? 1.0 : atm_min_half_fraction(R, h, lit_hi, L.H_g);
				float haze_lo = atm_min_half_fraction(R, h, lit.x, H_haze);
				float haze_hi = open ? 1.0 : atm_min_half_fraction(R, h, lit_hi, H_haze);
				vec3 gas_a = gas_half * (near ? 1.0 - gas_hi : 1.0 + gas_lo);
				vec3 gas_b = gas_half * (near ? 1.0 - gas_lo : 1.0 + gas_hi);
				vec3 haze_a = haze_half * (near ? 1.0 - haze_hi : 1.0 + haze_lo);
				vec3 haze_b = haze_half * (near ? 1.0 - haze_lo : 1.0 + haze_hi);
				vec3 upper_half = gas_upper ? gas_half : haze_half;
				vec3 lower_half = gas_upper ? haze_half : gas_half;
				vec3 upper_run = gas_upper ? exp(-gas_a) - exp(-gas_b) : exp(-haze_a) - exp(-haze_b);
				vec3 lower_run = gas_upper ? exp(-haze_a) - exp(-haze_b) : exp(-gas_a) - exp(-gas_b);
				vec3 upper_source = gas_upper ? vec3(gas_source) : L.scatter_h;
				vec3 lower_source = gas_upper ? L.scatter_h : vec3(gas_source);
				onion = upper_source * (near ? vec3(1.0) : exp(-2.0 * lower_half)) * upper_run
						+ lower_source * exp(-upper_half) * lower_run;
			}
			// The sun's column is held at the point that halves what the camera sees of the lit
			// part, taken on the luma.
			float luma_a = atm_luma(t_a);
			float luma_b = atm_luma(t_b);
			float t_mid = luma_a - log(0.5 * (1.0 + exp(luma_a - luma_b)));
			float luma_half = max(atm_luma(half_column), 1.0e-12);
			float f_mid = clamp(point == 1 ? 1.0 - t_mid / luma_half : t_mid / luma_half - 1.0,
					f_lo, f_hi);
			float v = atm_erfinv(min(f_mid, 0.99999));
			z = h + L.H_ref * v * v;
			float u = atm_chord(R, z, h);
			mu_v = u / (R + z);
			mu_s = (half_a + sign_s * u * sz) / (R + z);
		}
		vec3 view;
		vec3 source;
		vec3 sun;
		vec3 gas_v;
		vec3 haze_v;
		vec3 gas_s;
		vec3 haze_s;
		atm_min_point(L, R, z, mu_v, mu_s, h, gas_source, view, source, sun, gas_v, haze_v, gas_s,
				haze_s);
		if (point == 0) {
			total = 2.0 * view;
			per_depth = source / max(view, vec3(1.0e-12));
			gas_half = gas_v;
			haze_half = haze_v;
			continue;
		}
		float shadow = atm_sun_shadow(R, z, mu_s, sun_ang);
		vec3 mixed = per_depth * (exp(-t_a) - exp(-t_b));
		path += (stacked > 0.0 ? mix(mixed, onion, stacked) : mixed) * exp(-sun) * shadow;
	}
	tangent_transmittance = exp(-total);
	return path;
}

// The full tier's atm_ring_pixel(), filter and all, with each tap's ray from atm_min_tangent()
// and the pixel's own disc-hit ray from atm_disc().
bool atm_ring_pixel(AtmLayers L, float R, float h, float footprint, float qs, float sz,
		float sun_ang, bool with_disc, float mu, float mu0, float far_floor, out vec3 path,
		out vec3 transmittance, out vec3 disc_path) {
	path = vec3(0.0);
	transmittance = vec3(1.0);
	disc_path = vec3(0.0);
	float half_width = 0.5 * ATM_RING_FILTER_PX * footprint;
	float lo = max(h - half_width, 0.0);
	float hi = min(h + half_width, atm_ring_reach(L));
	bool has_taps = hi > lo;
	float span = hi - lo;
	int taps = has_taps ? int(clamp(ceil(span / min(L.H_ref, footprint)), 1.0,
			float(iv_atm_ring_max_taps))) : 0;
	float step = span / float(max(taps, 1));
	float cdf_below = atm_tent_cdf((lo - h) / half_width);
	vec3 transmittance_sum = vec3(0.0);
	float weight_sum = 0.0;
	for (int i = 0; i < taps; i++) {
		float tap_h = lo + (float(i) + 0.5) * step;
		vec3 tap_transmittance;
		vec3 ray_path = atm_min_tangent(L, R, tap_h, qs, sz, sun_ang, tap_transmittance);
		float cdf_above = atm_tent_cdf((lo + float(i + 1) * step - h) / half_width);
		float weight = cdf_above - cdf_below;
		cdf_below = cdf_above;
		path += ray_path * weight;
		transmittance_sum += tap_transmittance * weight;
		weight_sum += weight;
	}
	if (with_disc) {
		vec3 unused_transmittance;
		atm_disc(L, R, mu, mu0, sz, sun_ang, far_floor, disc_path, unused_transmittance);
	}
	if (!has_taps || weight_sum <= 0.0) {
		return false;
	}
	transmittance = mix(vec3(1.0), transmittance_sum / weight_sum, min(weight_sum, 1.0));
	return true;
}
