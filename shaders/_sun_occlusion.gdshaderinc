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
// any zoom and farwarp-immune. Apply the result via AO with
// AO_LIGHT_AFFECT = 1.0 (attenuates direct light without a custom light(),
// which would break the tuned METER = 1e-3 shadow path).
//
// Currently ring-plane transmission only; analytic spheroid occluders
// (eclipses, moon transits) are the planned companion term.


// Transmission through an annular ring layer, modeled as a 1D radial opacity
// profile in a thin plane. [param ring_alpha_r8] spans radius
// [param ring_texture_inner] to [param ring_texture_outer] (the padded texture
// range, not the physical ring edges) and must have mipmaps: the sampled LOD
// matches the penumbra footprint from [param sun_angular_radius], which is how
// the shadow edge gets its physically correct softness. All positions/lengths
// share one frame and unit (world space in practice); [param sun_direction]
// and [param ring_normal] are unit vectors, either normal sign works.
float sun_occlusion_ring_transmission(vec3 world_position, vec3 sun_direction,
		vec3 ring_center, vec3 ring_normal, float ring_texture_inner,
		float ring_texture_outer, float sun_angular_radius,
		sampler2D ring_alpha_r8, float ring_alpha_width) {
	// Degenerate geometry falls through branchless (clamped cosine, then the
	// range test below): fwidth() needs texture_u defined in every quad lane,
	// so no early return may precede it.
	float cos_slant = dot(ring_normal, sun_direction);
	float abs_cos = max(abs(cos_slant), 1e-4);
	float signed_cos = (cos_slant >= 0.0) ? abs_cos : -abs_cos;
	float ray_length = dot(ring_normal, ring_center - world_position) / signed_cos;
	vec3 plane_hit = world_position + sun_direction * ray_length - ring_center;
	float texture_u = (length(plane_hit) - ring_texture_inner)
			/ (ring_texture_outer - ring_texture_inner);
	float screen_texels = fwidth(texture_u) * ring_alpha_width;
	if (ray_length <= 0.0 || texture_u <= 0.0 || texture_u >= 1.0) {
		return 1.0; // ring plane not sunward, or outside the profile range
	}
	// The sun's angular size smears the shadow over a penumbra footprint: sample
	// the mip level whose texel size matches it. Also floor the LOD at the
	// screen-space footprint (what auto-LOD texture() would use), so sub-pixel
	// ringlet shadows filter instead of aliasing into dashes.
	float penumbra_width = 2.0 * sun_angular_radius * ray_length;
	float texel_size = (ring_texture_outer - ring_texture_inner) / ring_alpha_width;
	float filter_texels = max(penumbra_width / texel_size, screen_texels);
	float lod = log2(max(filter_texels, 1.0));
	float alpha = textureLod(ring_alpha_r8, vec2(texture_u, 0.5), lod).r;
	// A slanted path through the ring layer scales optical depth by 1/cos.
	return pow(1.0 - alpha, 1.0 / abs_cos);
}
