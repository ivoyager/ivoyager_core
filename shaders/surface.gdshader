// surface.gdshader
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
// skip_vertex_transform: for the farwarp vertex remap; see _farwarp.gdshaderinc.
// ambient_light_disabled: ambient is rebuilt as emission; see _sun_occlusion.gdshaderinc.
render_mode skip_vertex_transform, ambient_light_disabled;

// Lit surface shader for a solid IVShellsModel surface (shell 0) that removes the texel
// "squares" a fixed-resolution map shows when magnified at close (orbital) range. Its core
// job: resample the albedo and normal maps BICUBIC (C2-continuous) so the magnified
// map reads smooth instead of blocky. It also hosts the analytic ring-shadow term (see
// _sun_occlusion.gdshaderinc), enabled per body by its IVRings node; off by default.
// No synthesized or sharpened detail is added — that was
// explored on the Moon and intentionally dropped (see IMAGE_ENHANCEMENT_EXPLORATION.md in the
// plugin root for what was tried, why it didn't pay off, and the directions that would:
// offline super-resolution of the source maps, and structure-guided shader synthesis).
//
// Named in a shells.tsv "shader" column: on a surface-class row (the default for
// rocky/desert/gas-giant/etc.), or per-body in a SHELL_<body>_SURFACE shell-0 row.
// Discovered channels auto-bind to the like-named uniforms (albedo, normal, roughness, emission);
// each table override column feeds the uniform of the same name, so the scalars below are tunable.
//
// LIGHTING: no custom light(); writes ALBEDO/NORMAL_MAP/ROUGHNESS/EMISSION and lets the engine's
// default PBR + shadow path light it. Disc photometry (the falloff toward limb and terminator)
// rides on ALBEDO instead - see _photometry.gdshaderinc and the lunar_lambert uniform.
//
// CITY LIGHTS: emission defaults to black (hint_default_black), so a body with no emission map
// emits nothing; one that ships a map gets additive emission (night side, washed out by day).

#include "_detail.gdshaderinc"
#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_photometry.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"
#include "_atmosphere.gdshaderinc"
#include "_point_spread_function.gdshaderinc" // body_pixel_radius / body_disc_weight (the handoff)

// Auto-bound channels. Default hints make an unbound map a no-op (see asset_preloader.gd
// texture_channels). normal/roughness stay LINEAR (no source_color); albedo/emission decode sRGB.
uniform sampler2D albedo : source_color;                        // surface color map
uniform sampler2D normal : hint_normal;                         // tangent-space; unbound = flat
uniform sampler2D roughness : hint_default_white;               // unbound = white -> roughness_scale
uniform sampler2D emission : source_color, hint_default_black;  // city lights; unbound = no emission

// Tint multiplied into the sampled albedo (alpha unused; this surface is opaque). White
// leaves a mapped body untouched. IVShellsModel sets it to the surface class's
// fallback_color when the body ships no color map at all, and an unbound albedo sampler
// reads white, so the body renders in that flat color instead of white.
uniform vec4 albedo_color : source_color = vec4(1.0);

// Affine range unpacking for a range-tagged albedo (IVAssetPreloader.parse_range_tags).
// A tagged file stores (physical - lo) / (hi - lo), so the map spends all 256 codes on the
// reflectance the body actually has instead of on the [0,1] it does not; the defaults below
// are the identity, so an untagged map is byte-for-byte the same render as before. Affine is
// the whole point: it commutes with filtering and mip selection, so a packed map mips
// correctly, and it maps a flat fill to a flat fill, which is what keeps an unimaged region a
// single BC1 block. Applied BEFORE albedo_color, which is a tint on physical reflectance.
uniform vec3 albedo_range_lo = vec3(0.0);
uniform vec3 albedo_range_hi = vec3(1.0);

// Material scalars (per-body tunable via shells.tsv columns of the same name).
uniform float normal_scale = 1.0;      // strength of the bound tangent normal map
uniform float roughness_scale = 1.0;   // multiplies the sampled roughness (white if unbound)
uniform float metallic = 0.0;
uniform float metallic_specular = 0.5; // dielectric specular reflectance; 0.5 = StandardMaterial3D default
// The emission map's two mutually exclusive level channels, each paired with the global
// that scales it (shells.tsv authors both columns; IVExposureManager zeroes one of the
// globals, so a shell needs no knowledge of which lighting model is running).
uniform float emission_energy_multiplier = 1.0; // nonphysical, by-eye; StandardMaterial3D's name
uniform float emission_luminance = 0.0;         // physical, cd/m^2 at a full-white texel
// Lunar-Lambert L (see _photometry.gdshaderinc): 0.0 = Lambert, the exact-no-op default;
// 1.0 = Lommel-Seeliger, a flat disc at zero phase. Set per surface class in shells.tsv.
uniform float lunar_lambert : hint_range(0.0, 1.0) = 0.0;
// Minnaert k, the OTHER direction (see _photometry.gdshaderinc): 1.0 = Lambert, the exact-no-op
// default; above 1.0 darkens the limb, which no lunar_lambert can do. Carried here so a body
// with a MAP can hold that direction at all -- the cloud-deck shaders have had both laws, while
// a mapped surface could only ever flatten its disc. Shipped bodies set neither: Uranus and
// Neptune measure k < 1 and take lunar_lambert instead, and Jupiter and Saturn have no measured
// value (see PHOTOMETRIC_MODEL.md). Note the two are coupled to LEVEL through the disc factor
// F = 2/(2k+1), so a body adopting one must re-derive its map level against A x F = p.
uniform float minnaert_k : hint_range(1.0, 2.0) = 1.0;
global uniform float iv_emission_energy_scale;    // 1.0 with physical light off, else 0.0
global uniform float iv_emission_luminance_scale; // rendered units per cd/m^2; 0.0 with physical light off

// Disc/point handoff, set each frame by IVShellsModel's disc LOD from IVBody.psf_handoff:
// as the body shrinks toward a pixel its IVBodyPSF quad's core takes over and this disc
// discards, resolved against its OWN VIEWPORT_SIZE -- so an off-screen capture switches at
// its own buffer's scale rather than the main window's. IVBodyPSF collapses the two edges to
// one for a lit body, making the trade a step at a size the handoff solve has matched; only
// an emissive disc (sun_surface, already transparent) can afford to crossfade. The defaults
// saturate fully ON, so a body with no quad (nothing to hand off to, and its fixed distance
// cull still in place) renders exactly as it did before this existed.
uniform float angular_radius = 0.0; // body mean radius / camera distance
uniform float handoff_low = -2.0;   // px on-screen radius at/below which the quad replaces this
uniform float handoff_high = -1.0;  // px at/above which this disc fully replaces the quad's core


varying vec3 v_world_position; // true world position; VERTEX is farwarp-remapped
varying vec3 model_position;   // unit-sphere local position (captured before farwarp overwrites VERTEX)
varying vec3 v_camera_local;   // the camera in this shell's local frame, for atm_disc_air()
varying vec3 v_sun_local;      // the sun direction in that frame, unit
varying flat float v_far_floor; // atm_far_floor() is uniform-only: per vertex, not per fragment
varying flat float v_disc_weight; // disc/point trade; >0 draw, 0 handed off (a step here)


void vertex() {
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	model_position = VERTEX;
	if (atm_present()) {
		// The ray geometry for atm_disc_air() runs in the shell's own frame, where the
		// (oblate) shell is the unit sphere; see atmosphere_limb.gdshader. Skipped on an
		// airless body, whose varyings then go unread.
		mat4 inverse_model = inverse(MODEL_MATRIX);
		v_camera_local = (inverse_model * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
		v_sun_local = normalize(mat3(inverse_model) * sun_direction);
		v_far_floor = atm_far_floor();
	}
	// Farwarp compresses the surface along the camera ray so a large body's depth stays
	// consistent with the per-vertex-warped orbit lines around it. _tbn: the normal map needs TBN.
	farwarp_lit_vertex_tbn(MODELVIEW_MATRIX, MODELVIEW_NORMAL_MATRIX, VERTEX, NORMAL, TANGENT, BINORMAL);
	v_disc_weight = body_disc_weight(body_pixel_radius(angular_radius,
			PROJECTION_MATRIX[1][1], VIEWPORT_SIZE.y), handoff_low, handoff_high);
}


void fragment() {
	// Below the handoff the body's IVBodyPSF quad has taken over and this disc must go. It
	// goes by DISCARD rather than by fading ALPHA, and that is not a style choice: writing
	// ALPHA moves this material to the transparent pass, where it stops writing depth and so
	// stops occluding anything -- the star field through a night side, bodies not sorting
	// against each other, and the body's own quad drawing through it. Discarding keeps the
	// surface opaque and the whole depth model intact. Resolved here rather than by a CPU
	// "visible" flag, which could only ever answer for the viewport its node lives in.
	if (v_disc_weight <= 0.0) {
		discard;
	}
	// Bicubic resample removes the texel squares of the magnified maps (texture_bicubic lives
	// in _detail_common.gdshaderinc); plain texture() for the scalar-fallback roughness.
	// Decoded on the way in and encoded on the way out (see _display.gdshaderinc), so every
	// colour term between the two is a linear reflectance -- which is what a range tag, a
	// disc law and an atmosphere's transmittance all state.
	ALBEDO = display_decode(texture_bicubic(albedo, UV).rgb);
	ALBEDO = albedo_range_lo + (albedo_range_hi - albedo_range_lo) * ALBEDO;
	ALBEDO *= display_decode(albedo_color.rgb);
	ROUGHNESS = clamp(texture(roughness, UV).r * roughness_scale, 0.0, 1.0);
	METALLIC = metallic;
	SPECULAR = metallic_specular;

	vec3 n = texture_bicubic(normal, UV).xyz * 2.0 - 1.0;
	n.xy *= normal_scale;
	n = normalize(n);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// Emission map (black if none). Exactly one of the two global scales is nonzero, so
	// summing the channels selects the running one without a branch.
	EMISSION = display_decode(texture_bicubic(emission, UV).rgb)
			* (emission_energy_multiplier * iv_emission_energy_scale
			+ emission_luminance * iv_emission_luminance_scale);

	// Rebuilt ambient (engine ambient is disabled; see render_mode). Added before
	// the shadow so occlusion removes sunlight, not starlight; see the include.
	// Kept for the twilight term below, which is DIFFUSE light and so takes the
	// unfactored albedo, exactly as the isotropic ambient on the next line does.
	vec3 unlit_albedo = ALBEDO;
	EMISSION += ALBEDO * ambient_light; // the feed already carries exposure; see the include

	// Disc photometry, AFTER the isotropic ambient above (which takes the unfactored
	// albedo) and independent of the shadow multiply below. NORMAL is still the
	// interpolated macroscopic normal here - the engine applies NORMAL_MAP after
	// fragment() - which is exactly what a disc law wants. VIEW survives farwarp
	// unchanged: the remap scales a view-space position along its own ray, so screen
	// direction, and therefore VIEW, is untouched.
	vec3 macro_normal = normalize(NORMAL);
	vec3 sun_view = normalize(mat3(VIEW_MATRIX) * sun_direction);
	float atm_beam_response = minnaert_albedo_factor(macro_normal, sun_view, VIEW, minnaert_k)
			* lunar_lambert_albedo_factor(macro_normal, sun_view, VIEW, lunar_lambert);
	ALBEDO *= atm_beam_response;
	// The body's atmosphere above this shell (the limb row's atm_* columns, propagated
	// here; an exact no-op without them): direct light reddened along the sun path, and
	// the chromatic half of the view-path extinction whose luma the atm_disc_air() block
	// below removes. See _atmosphere.gdshaderinc.
	float atm_mu0 = dot(macro_normal, sun_view);
	float atm_mu = dot(macro_normal, VIEW);
	vec3 atm_tint = atm_view_tint(atm_mu);
	vec3 atm_sun_t = atm_sun_transmittance(atm_mu0);
	ALBEDO *= atm_sun_t * atm_tint;
	// The sun angle averaged across this pixel's radial extent, which one shading sample cannot
	// resolve at the rim (see limb_mean_incidence). The engine's diffuse carries
	// albedo * mu0, so rescaling ALBEDO delivers the mean wherever mu0 is positive; where the
	// centre sample missed the sliver entirely no albedo factor can reach it, and that
	// remainder goes to emission below. Formed here with the other screen-derivative terms,
	// under uniform control flow. It also reports the pixel's coverage by this shell, which
	// is applied at the very end.
	float limb_mu0_centre = max(atm_mu0, 0.0);
	float limb_fade; // the pixel's coverage by this shell
	float limb_specular_fade; // the silhouette fade specular alone keeps
	float limb_mu0_mean = limb_mean_incidence(macro_normal, VIEW, sun_view, atm_mu,
			limb_radius_px(v_world_position, MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD,
			PROJECTION_MATRIX[1][1], VIEWPORT_SIZE.y), limb_fade, limb_specular_fade);
	float limb_engine_mu0 = min(limb_mu0_mean, LIMB_INCIDENCE_ALBEDO_MAX * limb_mu0_centre);
	float limb_emission_mu0 = limb_mu0_mean - limb_engine_mu0;
	if (limb_mu0_centre > 0.0) {
		float limb_ratio = limb_engine_mu0 / limb_mu0_centre;
		ALBEDO *= limb_ratio;
		SPECULAR *= sqrt(limb_ratio); // F0 scales as SPECULAR^2
	}

	float sun_visible = 1.0;
	if (ring_texture_outer > 0.0 || occluder_count > 0) {
		sun_visible = sun_occlusion_visible_fraction(v_world_position);
		if (compat_albedo_shadow) {
			ALBEDO *= sun_visible;
			// AO is ambient-only on this renderer, so the albedo multiply stands in for
			// it -- and the SPECULAR lobe needs the same shadow, or an eclipsed body
			// keeps its full sunlit sheen, which a dark-adapted exposure amplifies into
			// a solid white disc (measured: Mimas in Saturn's shadow). F0 scales as
			// SPECULAR^2, so the square root carries the fraction onto specular energy.
			SPECULAR *= sqrt(sun_visible);
		} else {
			AO = sun_visible;
			AO_LIGHT_AFFECT = 1.0; // attenuates direct light, not just ambient
		}
	}

	// The twilight this shell is lit by once the plane-parallel beam has run out, which
	// is what the engine's own N.L cannot carry: it is zero at mu0 = 0 and the sky is not.
	// EMISSION for that reason, so it needs the shadow applied by hand (emission sits
	// outside the AO path) -- it is sunlight, unlike the starlight ambient above. Exactly
	// zero wherever the beam still dominates, so the day side is untouched; see the
	// include for why the subtraction inside makes that identical rather than merely small.
	// It takes the disc law's ISOTROPIC response and not the beam factor above: this light
	// arrives from the whole sky, and mu0^(k-1) is an answer about one incidence angle. On a
	// Lambert body both are 1 and nothing changes; on Venus the beam factor had been
	// collapsing the twilight toward the terminator exactly where it takes over.
	float atm_sky_response = minnaert_isotropic_response(macro_normal, VIEW, minnaert_k)
			* lunar_lambert_isotropic_response(macro_normal, VIEW, lunar_lambert);
	EMISSION += unlit_albedo * atm_sky_excess(atm_mu0, atm_sky_response,
			atm_beam_response) * atm_tint * (sun_light_energy * sun_visible);
	// The share of the pixel's mean sun angle the engine's own N.L cannot deliver, because at
	// this pixel that N.L is zero (see limb_mean_incidence). Direct sunlight, so it takes the
	// beam response, the sun path's transmittance and the tint exactly as the lit albedo did.
	EMISSION += unlit_albedo * atm_beam_response * atm_sun_t * atm_tint * limb_emission_mu0
			* (sun_light_energy * sun_visible);

	// The air in FRONT of this fragment (atm_disc_air: the veil over the lit disc, the
	// twilight glow past the terminator, the far half of a ray whose disc is an optical
	// limb), composited here rather than blended by the limb shell — in the fragment the
	// sum runs in linear light on every renderer, where the blend does not (THE
	// COMPOSITING SPLIT in the include). The luma is what the limb's alpha used to remove
	// from everything behind it: lit albedo, every emission term above, and the specular
	// lobe as its square root (F0 scales as SPECULAR^2, as for the shadow above). The
	// path stands in front, undimmed — and, like the shell term it replaces, un-eclipsed.
	vec3 atm_path;
	float atm_behind_luma;
	atm_disc_air(v_camera_local, model_position, v_sun_local, sun_angular_radius,
			v_far_floor, atm_path, atm_behind_luma);
	ALBEDO *= atm_behind_luma;
	SPECULAR *= sqrt(atm_behind_luma);
	EMISSION = EMISSION * atm_behind_luma + atm_path * sun_light_energy;

	// The pixel's coverage by this shell goes last, so it takes every term above it --
	// except specular, which keeps the silhouette fade instead (see limb_mean_incidence).
	ALBEDO *= limb_fade;
	SPECULAR *= sqrt(limb_specular_fade);
	EMISSION *= limb_fade;

	ALBEDO = display_write_albedo(ALBEDO);
	EMISSION = display_write(EMISSION);
}
