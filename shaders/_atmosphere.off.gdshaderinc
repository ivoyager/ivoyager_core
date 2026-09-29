// _atmosphere.off.gdshaderinc
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

// The disc shaders' entry points for the Off tier of Atmosphere Quality. _atmosphere.gdshaderinc
// includes this file in place of its quadrature and its limb where a shader has defined ATM_OFF
// (THE OFF VARIANT in that file's header); never include it on its own.
//
// They draw a body's air in CLOSED FORM: the same atm_* uniforms, layers and composite as the
// full tier, over a plane-parallel slab with a spherical airmass per layer, lit where the full
// tier's shadow test says. So a surface map that assumes the air on top of it keeps its colour,
// and a disc keeps the softening its air gives it toward the limb, for a small part of the
// quadrature's cost to compile and to draw. A body with no atmosphere gets exact no-ops from
// them. The model and what it gives up are *The Off tier* under *Atmospheres* in
// PHOTOMETRIC_MODEL.md.
//
// HAZARD: this draws the disc's air all the way out to the silhouette, where the full tier hands
// the rim to the limb shell (ATM_RIM_HANDOFF). A body bound to this variant must not also draw a
// limb shell, or its rim takes its air twice.

// A layer's airmass at zenith cosine mu from radius r, x = r / H: the path through a homogeneous
// shell of height 4 H / pi, which puts it at Chapman's sqrt(pi x / 2) along the horizon.
// Rationalized, so a ray near the zenith does not difference two terms of order x.
float atm_airmass(float mu, float x) {
	float shell_x = 0.78539816 * x;
	float mu_x = max(mu, 0.0) * shell_x;
	return (2.0 * shell_x + 1.0) / (sqrt(mu_x * mu_x + 2.0 * shell_x + 1.0) + mu_x);
}

// The exponential layers' slant columns above altitude z along a ray climbing at zenith cosine
// mu >= 0: the gas's per unit atm_gas_tau, the haze's carrying its own tau.
void atm_climb_columns(AtmLayers L, float R, float z, float mu, out float gas, out vec3 haze) {
	float r = R + z;
	gas = exp(-z / L.H_g) * atm_airmass(mu, r / L.H_g);
	// A haze with a top is two exponentials joined at it (atm_layers()), and below the top its
	// vertical column holds the upper one's whole column too.
	bool above_top = L.z_k > 0.0 && z > L.z_k;
	float top_deficit = L.z_k > 0.0 ? exp(-L.z_k / L.H_h) * (1.0 - L.H_t / L.H_h) : 0.0;
	vec3 vertical = above_top ? L.tau_t * exp(-z / L.H_t)
			: atm_haze_tau * (exp(-z / L.H_h) - top_deficit);
	haze = vertical * atm_airmass(mu, r / (above_top ? L.H_t : L.H_h));
}

// The slant extinction columns above altitude z of a disc of radius R, along zenith cosine mu:
// `gas` per unit atm_gas_tau, as L.scatter_g takes it, and `haze` and `layer` carrying their own
// taus, as L.scatter_h and L.scatter_l take them. A ray below the horizon descends to its tangent
// altitude before it climbs out, which is twice the horizontal column there less the climb from
// here that its other half does not repeat.
void atm_slant_columns(AtmLayers L, float R, float z, float mu, out float gas, out vec3 haze,
		out vec3 layer) {
	float r = R + z;
	float sin2 = max(1.0 - mu * mu, 0.0);
	bool descends = mu < 0.0;
	float tangent_z = max(r * sqrt(sin2) - R, 0.0);
	gas = 0.0;
	haze = vec3(0.0);
	for (int i = 0; i < (descends ? 2 : 1); i++) {
		float climb_gas;
		vec3 climb_haze;
		atm_climb_columns(L, R, i == 0 ? z : tangent_z, i == 0 ? abs(mu) : 0.0, climb_gas,
				climb_haze);
		float weight = i == 1 ? 2.0 : (descends ? -1.0 : 1.0);
		gas += weight * climb_gas;
		haze += weight * climb_haze;
	}
	layer = vec3(0.0);
	if (L.has_layer) {
		// A thin shell at the layer's centre radius, which a ray from beneath it crosses once.
		float ratio = min(r / (R + L.z_c), 1.0);
		layer = atm_layer_tau * (1.0 - smoothstep(-2.0, 2.0, (z - L.z_c) / L.sigma))
				* inversesqrt(max(1.0 - ratio * ratio * sin2, 1.0e-4));
	}
}

float atm_far_floor() {
	return 0.0;
}

// What atm_disc_air() of the full tier returns, for the same inputs and with the same composite
// (THE COMPOSITING SPLIT in _atmosphere.gdshaderinc): the path radiance in front of the disc
// and the luma of the disc's view transmittance.
void atm_disc_air(vec3 camera_local, vec3 fragment_local, vec3 sun_local, float sun_ang,
		float far_floor, out vec3 path, out float behind_luma) {
	path = vec3(0.0);
	behind_luma = 1.0;
	if (!atm_present()) {
		return;
	}
	float k = body_radius_km * shell_scale;       // km per local unit
	float R = body_radius_km * surface_scale;     // the disc, km
	vec3 c = camera_local * k;
	vec3 d = normalize(fragment_local * k - c);   // the view ray, camera -> fragment
	vec3 n = normalize(fragment_local);
	if (shell_scale > surface_scale) {
		// A shell above the disc takes the air in front of the disc behind it, and none where
		// its ray misses the disc.
		float tc = -dot(c, d);
		vec3 q = c + tc * d;
		float b_ray = length(q);
		if (b_ray >= R) {
			return;
		}
		n = (q - sqrt(max(R * R - b_ray * b_ray, 0.0)) * d) / R;
	}
	// A silhouette facet can present a view cosine just below zero, which is not a ray under the
	// horizon.
	float mu = max(dot(n, -d), 0.0);
	float mu0 = dot(n, sun_local);
	float sz = dot(-d, sun_local);
	AtmLayers L = atm_layers(-sz); // cos(theta) = dot(s, d)
	// Only the part of the ray the sun lights scatters, and the full tier's shadow test finds it:
	// past the terminator the planet's shadow starts it above the ground, and a ray that climbs
	// toward a camera on the night side can re-enter the shadow, which ends it short of the top.
	vec2 lit = atm_lit_interval(R, R * R * (1.0 - mu0 * mu0), R * mu0, sz, R * (mu - mu0 * sz),
			max(1.0 - sz * sz, 1.0e-12));
	bool capped = lit.y < ATM_INF;
	// The columns, from one loop (THE STRUCTURE in _atmosphere.gdshaderinc): the view ray's from
	// the ground, for what lies beneath; the view ray's and the sun's from where the lit part
	// starts; and, where it is capped, the same from where it ends.
	float gas_ground = 0.0;
	vec3 haze_ground = vec3(0.0);
	vec3 layer_ground = vec3(0.0);
	float gas_view_start = 0.0;
	vec3 haze_view_start = vec3(0.0);
	vec3 layer_view_start = vec3(0.0);
	float gas_sun_start = 0.0;
	vec3 haze_sun_start = vec3(0.0);
	vec3 layer_sun_start = vec3(0.0);
	float gas_view_end = 0.0;
	vec3 haze_view_end = vec3(0.0);
	vec3 layer_view_end = vec3(0.0);
	float gas_sun_end = 0.0;
	vec3 haze_sun_end = vec3(0.0);
	vec3 layer_sun_end = vec3(0.0);
	for (int i = 0; i < (capped ? 5 : 3); i++) {
		float u = i < 3 ? lit.x : min(lit.y, 1.0e9);
		float climb = u * (2.0 * R * mu + u);
		float z = i == 0 ? 0.0 : max(climb / (sqrt(R * R + climb) + R), 0.0);
		float cosine = mu;
		if (i > 0) {
			cosine = i % 2 == 1 ? (R * mu + u) / (R + z) : (R * mu0 + u * sz) / (R + z);
		}
		float column_gas;
		vec3 column_haze;
		vec3 column_layer;
		atm_slant_columns(L, R, z, cosine, column_gas, column_haze, column_layer);
		if (i == 0) {
			gas_ground = column_gas;
			haze_ground = column_haze;
			layer_ground = column_layer;
		} else if (i == 1) {
			gas_view_start = column_gas;
			haze_view_start = column_haze;
			layer_view_start = column_layer;
		} else if (i == 2) {
			gas_sun_start = column_gas;
			haze_sun_start = column_haze;
			layer_sun_start = column_layer;
		} else if (i == 3) {
			gas_view_end = column_gas;
			haze_view_end = column_haze;
			layer_view_end = column_layer;
		} else {
			gas_sun_end = column_gas;
			haze_sun_end = column_haze;
			layer_sun_end = column_layer;
		}
	}
	// Each layer's light attenuated along both legs: its source over the lit part times the
	// mean of e^-t as the view-plus-sun column t runs from the part's top to its start. MIXED,
	// the layers share one column; STACKED, each exponential has its own and the lower one's
	// light crosses the whole upper one too. atm_stacking() blends them, as for Min.
	vec3 gas_source = L.scatter_g * (gas_view_start - gas_view_end);
	vec3 haze_source = L.scatter_h * (haze_view_start - haze_view_end);
	vec3 layer_source = L.scatter_l * (layer_view_start - layer_view_end);
	vec3 gas_top = atm_gas_tau * (gas_view_end + gas_sun_end);
	vec3 gas_start = atm_gas_tau * (gas_view_start + gas_sun_start);
	vec3 haze_top = haze_view_end + haze_sun_end;
	vec3 haze_start = haze_view_start + haze_sun_start;
	vec3 mixed_mean = atm_exp_mean(gas_top + haze_top + layer_view_end + layer_sun_end,
			gas_start + haze_start + layer_view_start + layer_sun_start);
	path = (gas_source + haze_source + layer_source) * mixed_mean;
	bool gas_upper;
	float stacked = atm_stacking(L, L.H_h, gas_upper);
	if (stacked > 0.0) {
		vec3 stacked_path = gas_source * atm_exp_mean(gas_top, gas_start)
				* (gas_upper ? vec3(1.0) : exp(-haze_start))
				+ haze_source * atm_exp_mean(haze_top, haze_start)
				* (gas_upper ? exp(-gas_start) : vec3(1.0))
				+ layer_source * mixed_mean;
		path = mix(path, stacked_path, stacked);
	}
	path *= mix(1.0, atm_intensity, iv_limb_scale);
	behind_luma = atm_luma(exp(-(atm_gas_tau * gas_ground + haze_ground * L.delta_h
			+ layer_ground * L.delta_l)));
}

// What atm_receiver_light() of the full tier returns, for the same inputs: the tint, the sun
// transmittance at this shell's altitude, and the disc's plane-parallel diffuse for
// atm_sky_excess().
void atm_receiver_light(float mu, float mu0, out vec3 tint, out vec3 sun_transmittance,
		out vec3 plane_diffuse) {
	tint = vec3(1.0);
	sun_transmittance = vec3(1.0);
	plane_diffuse = vec3(0.0);
	if (!atm_present()) {
		return;
	}
	AtmLayers L = atm_layers(0.0);
	float R = body_radius_km * surface_scale;
	float z = max((shell_scale - surface_scale) * body_radius_km, 0.0);
	float up = max(mu0, 0.0);
	float b_ray = R * sqrt(max(1.0 - mu * mu, 0.0));
	vec3 disc_view = vec3(1.0);
	vec3 own_view = vec3(1.0);
	// The columns, from one loop (THE STRUCTURE in _atmosphere.gdshaderinc) in the full tier's
	// order: the view ray above the disc, the sun path above this shell; for a deck, the view ray
	// above the deck and the sun path above the disc.
	for (int i = 0; i < (z > 0.0 ? 4 : 2); i++) {
		bool view = i % 2 == 0;
		float column_z = i == 1 || i == 2 ? z : 0.0;
		float r = R + column_z;
		// the view ray's zenith cosine at this altitude, from its impact parameter
		float cosine = view ? sqrt(max(1.0 - b_ray * b_ray / (r * r), 0.0)) : up;
		float gas;
		vec3 haze;
		vec3 layer;
		atm_slant_columns(L, R, column_z, cosine, gas, haze, layer);
		if (view) {
			vec3 transmittance = exp(-(atm_gas_tau * gas + haze * L.delta_h + layer * L.delta_l));
			if (i == 0) {
				disc_view = transmittance;
			}
			own_view = transmittance;
		} else {
			vec3 total = atm_sun_transmittance_of(L, atm_gas_tau * gas, haze, layer);
			if (i == 1) {
				sun_transmittance = total;
			}
			if (i == 3 || z <= 0.0) {
				plane_diffuse = up * max(total - exp(-(atm_gas_tau * gas + haze + layer)),
						vec3(0.0));
			}
		}
	}
	tint = own_view / max(atm_luma(disc_view), 1.0e-6);
}
