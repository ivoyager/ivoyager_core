// _sun_occlusion.gdshaderinc
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

// Analytic sun occlusion for lit materials: the fraction of direct sunlight
// reaching a fragment, computed per-fragment from true-space geometry uniforms
// instead of shadow maps. Shadow maps can't serve astronomical-scale casters:
// their world-space texel footprint (tens to hundreds of km) is far coarser
// than real occluder structure (Saturn's ring profile, eclipse penumbrae), and
// under farwarp the caster geometry warps in light space while the receiver
// warps in camera space, so map shadows across the warp boundary are wrong by
// construction. Analytic terms use true positions only, so they are exact at
// any zoom and farwarp-immune.
//
// Two occluder kinds: a ring plane with a 1D radial opacity profile (ring
// shadows, with slant path and physical penumbra), and oblate spheroids as sky
// discs with exact disc-overlap (eclipses, transits; penumbra/antumbra fall
// out of the disc math). GDScript mirrors of the math live in IVAstronomy;
// keep them in exact sync.
//
// A receiving shader declares 'render_mode ambient_light_disabled', includes
// this file (which declares the shared uniform interface below), captures the
// TRUE world position in vertex() BEFORE the farwarp remap overwrites VERTEX,
// then in fragment():
//
//     EMISSION += ALBEDO * ambient_light; // rebuilt ambient; BEFORE the shadow
//     if (ring_texture_outer > 0.0 || occluder_count > 0) {
//         float sun_visible = sun_occlusion_visible_fraction(v_world_position);
//         if (compat_albedo_shadow) {
//             ALBEDO *= sun_visible;
//         } else {
//             AO = sun_visible;
//             AO_LIGHT_AFFECT = 1.0; // attenuates direct light, not just ambient
//         }
//     }
//
// The AO path needs no custom light(); it rides the engine's own PBR and shadow
// path. It does NOT work with the Compatibility renderer, where ao
// never reaches direct light (gles3 scene.glsl applies it to ambient only) -
// hence the compat_albedo_shadow albedo-multiply fallback (specular stays
// unshadowed there; accepted).
//
// The occlusion must remove DIRECT sunlight only, never ambient starlight. But
// AO multiplies engine ambient regardless of AO_LIGHT_AFFECT, the compat
// albedo multiply darkens everything albedo touches, and engine ambient can't
// be compensated exactly from a shader (with a sky present it includes
// sky-derived irradiance and reflection terms). So receivers opt OUT of engine
// ambient entirely (ambient_light_disabled) and rebuild diffuse ambient as
// emission from the manager-fed ambient_light uniform, which the occlusion
// then physically cannot touch: shadowed regions and the sun-less night side
// settle at the same ambient level. The manager feeds ambient_light even when
// IVCoreSettings.apply_analytic_shadows is off (the shadow terms are what that
// setting disables), so night sides never go black.
//
// NOTE FOR FUTURE MULTISTAR SUPPORT: this model assumes ONE star. The manager
// feeds a single sun_direction / sun_angular_radius and one occluder set, and
// the fragment applies a single sun_visible fraction through AO (or the compat
// albedo multiply) - both of which scale ALL direct light uniformly. Two stars
// cannot share that: a fragment eclipsed from star A but still lit by star B
// must keep B's light, which one AO value cannot express. Per-star shadows need
// per-light attenuation - a custom light() that evaluates each star's occlusion
// (viable again now that the METER scale-sensitivity that once ruled it out is
// resolved), or additive per-star passes. The occlusion math (sun_occlusion_*
// here and the IVAstronomy CPU mirrors) is already sun-parameterized, so it is
// reusable per star; only the application is single-sun.

// Fed per frame by the manager (or IVRings during the experiment); defaults
// keep every term a no-op until fed.
uniform sampler2D ring_alpha_r8 : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform float ring_alpha_width = 1.0;
uniform vec3 ring_center;
uniform vec3 ring_normal = vec3(0.0, 0.0, 1.0);
uniform float ring_texture_inner = 0.0;
uniform float ring_texture_outer = 0.0; // <= 0.0 disables the ring term
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0); // unit, toward the sun
uniform float sun_angular_radius = 0.0;
uniform vec4 occluder_data_a[6]; // xyz = center (world), w = equatorial radius
uniform vec4 occluder_data_b[6]; // xyz = pole axis (unit), w = polar radius
uniform int occluder_count = 0; // 0 disables the spheroid term
uniform bool compat_albedo_shadow = false; // see header: AO is ambient-only in gl_compatibility
uniform vec3 ambient_light = vec3(0.0); // scene ambient (color x energy), rebuilt as emission; see header


// Visible fraction of the sun's disc given an occluding disc: exact two-circle
// (lens) overlap in the planar small-angle approximation, with exact
// containment tests - so totality, annularity and partial phases all behave.
// All args in radians.
float sun_occlusion_disc_fraction(float sun_ang_radius, float occluder_ang_radius,
		float separation) {
	float a = max(sun_ang_radius, 1e-7);
	float b = occluder_ang_radius;
	float c = separation;
	if (c >= a + b) {
		return 1.0; // no overlap
	}
	if (c <= b - a) {
		return 0.0; // total: occluder covers the sun disc
	}
	if (c <= a - b) {
		return 1.0 - (b * b) / (a * a); // annular/transit: occluder inside the sun disc
	}
	if (b > 20.0 * a) {
		// A much larger occluder disc (e.g. Saturn seen from its rings, ~1700x
		// the sun disc): its edge is locally straight across the small sun
		// disc, and the exact lens formula below cancels catastrophically (an
		// a^2-scale result from b^2-scale terms - float32 noise sparkles along
		// the penumbra). Use the stable straight-edge chord fraction instead.
		float x = clamp((c - b) / a, -1.0, 1.0); // sun-center distance past the edge, in sun radii
		return 0.5 + (x * sqrt(1.0 - x * x) + asin(x)) / 3.14159265358979;
	}
	float a2 = a * a;
	float b2 = b * b;
	float c2 = c * c;
	float lens = a2 * acos(clamp((c2 + a2 - b2) / (2.0 * c * a), -1.0, 1.0))
			+ b2 * acos(clamp((c2 + b2 - a2) / (2.0 * c * b), -1.0, 1.0))
			- 0.5 * sqrt(max((a + b - c) * (c + a - b) * (c - a + b) * (c + a + b), 0.0));
	return 1.0 - lens / (3.14159265358979 * a2);
}


// Visible fraction of the sun's disc past one oblate-spheroid occluder
// ([param occluder_a] = center.xyz + equatorial radius, [param occluder_b] =
// pole axis.xyz (unit) + polar radius). Oblateness matters: Saturn's flattening
// is visible in its shadow on the rings.
float sun_occlusion_spheroid_fraction(vec3 world_position, vec3 sun_dir,
		float sun_ang_radius, vec4 occluder_a, vec4 occluder_b) {
	vec3 offset = occluder_a.xyz - world_position;
	float equatorial_radius = occluder_a.w;
	vec3 pole = occluder_b.xyz;
	float polar_radius = occluder_b.w;
	// Stretch space along the pole so the spheroid becomes a sphere of the
	// equatorial radius; the same affine map applies to the sun ray. (The sun
	// disc distorts by ~flattening x angular radius - negligible.)
	float stretch = equatorial_radius / polar_radius - 1.0;
	vec3 offset_stretched = offset + stretch * dot(offset, pole) * pole;
	vec3 sun_dir_stretched = normalize(sun_dir + stretch * dot(sun_dir, pole) * pole);
	float dist = length(offset_stretched);
	if (dist <= equatorial_radius) {
		return 1.0; // at/inside the occluder; the manager excludes self-occlusion
	}
	vec3 to_occluder = offset_stretched / dist;
	if (dot(to_occluder, sun_dir_stretched) <= 0.0) {
		return 1.0; // occluder is not sunward of the fragment
	}
	float occluder_angular_radius = asin(clamp(equatorial_radius / dist, 0.0, 1.0));
	float separation = acos(clamp(dot(to_occluder, sun_dir_stretched), -1.0, 1.0));
	return sun_occlusion_disc_fraction(sun_ang_radius, occluder_angular_radius, separation);
}


// Transmission through an annular ring layer, modeled as a 1D radial opacity
// profile in a thin plane. [param ring_alpha] spans radius [param texture_inner]
// to [param texture_outer] (the padded texture range, not the physical ring
// edges) and must have mipmaps: the sampled LOD matches the penumbra footprint
// from [param sun_ang_radius] (floored at the screen footprint, so sub-pixel
// ringlet shadows filter instead of aliasing into dashes), which is how the
// shadow edge gets its physically correct softness. All positions/lengths share
// one frame and unit (world space in practice); [param sun_dir] and
// [param plane_normal] are unit vectors, either normal sign works.
float sun_occlusion_ring_transmission(vec3 world_position, vec3 sun_dir,
		vec3 plane_center, vec3 plane_normal, float texture_inner,
		float texture_outer, float sun_ang_radius,
		sampler2D ring_alpha, float alpha_width) {
	// Degenerate geometry falls through branchless (clamped cosine, then the
	// range test below): fwidth() needs texture_u defined in every quad lane,
	// so no early return may precede it.
	float cos_slant = dot(plane_normal, sun_dir);
	float abs_cos = max(abs(cos_slant), 1e-4);
	float signed_cos = (cos_slant >= 0.0) ? abs_cos : -abs_cos;
	float ray_length = dot(plane_normal, plane_center - world_position) / signed_cos;
	vec3 plane_hit = world_position + sun_dir * ray_length - plane_center;
	float texture_u = (length(plane_hit) - texture_inner)
			/ (texture_outer - texture_inner);
	float screen_texels = fwidth(texture_u) * alpha_width;
	if (ray_length <= 0.0 || texture_u <= 0.0 || texture_u >= 1.0) {
		return 1.0; // ring plane not sunward, or outside the profile range
	}
	// The sun's angular size smears the shadow over a penumbra footprint: sample
	// the mip level whose texel size matches it.
	float penumbra_width = 2.0 * sun_ang_radius * ray_length;
	float texel_size = (texture_outer - texture_inner) / alpha_width;
	float filter_texels = max(penumbra_width / texel_size, screen_texels);
	float lod = log2(max(filter_texels, 1.0));
	float alpha = textureLod(ring_alpha, vec2(texture_u, 0.5), lod).r;
	// A slanted path through the ring layer scales optical depth by 1/cos.
	return pow(1.0 - alpha, 1.0 / abs_cos);
}


// Total sun-visible fraction for a fragment at TRUE (un-farwarped) world
// position, from the uniform interface above: ring transmission (when enabled)
// x product of spheroid occluder fractions (independent-occlusion
// approximation). Call under uniform control flow (the ring term uses fwidth).
float sun_occlusion_visible_fraction(vec3 world_position) {
	float visible = 1.0;
	if (ring_texture_outer > 0.0) {
		visible = sun_occlusion_ring_transmission(world_position, sun_direction, ring_center,
				ring_normal, ring_texture_inner, ring_texture_outer, sun_angular_radius,
				ring_alpha_r8, ring_alpha_width);
	}
	for (int i = 0; i < occluder_count; i++) {
		visible *= sun_occlusion_spheroid_fraction(world_position, sun_direction,
				sun_angular_radius, occluder_data_a[i], occluder_data_b[i]);
	}
	return visible;
}
