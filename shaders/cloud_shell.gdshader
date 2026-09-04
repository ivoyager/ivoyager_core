// cloud_shell.gdshader
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
//render_mode depth_prepass_alpha; // See note below

// Lit, translucent cloud overlay for an IVShellsModel shell. Name it in the
// shell's shells.tsv "shader" column; the shell's discovered "albedo" channel
// (<prefix>.<file_tag>.albedo.*) auto-binds to the uniform below. Default lit
// (no unshaded) so the sun still casts the day/night terminator across the deck.
//
// Purpose: a cloud albedo map at a fixed resolution looks soft and coarse when
// magnified at close (orbital) range — the texels are kilometers wide. This adds
// procedural fractal (FBM) detail at sub-texel scale so the deck keeps believable
// structure at any zoom, without a larger texture. The base map still owns the
// real, large-scale cloud shape.
//
// The clouds_* uniforms below are defaults; override any per body by adding a
// shells.tsv column of the same name to the shell's row (IVShellsModel feeds
// each such column to set_shader_parameter).
//
// "render_mode depth_prepass_alpha;" above in conjuction with default `cast_shadow`
// ON in shells.tsv ought to provide shadows, which ought to provide a nice depth
// effect when viewed from ISS. But I can't see it after carefull viewing, so
// it's currently disabled at both ends now.

#include "_detail.gdshaderinc"
#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_photometry.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"
#include "_atmosphere.gdshaderinc"
#include "_point_spread_function.gdshaderinc" // body_pixel_radius / body_disc_weight (the handoff)

uniform sampler2D albedo : source_color; // auto-bound: <prefix>.<file_tag>.albedo.*
uniform vec3 clouds_color : source_color = vec3(1.0); // tint over the map's own rgb
uniform float clouds_opacity = 1.0; // overall coverage multiplier
uniform float clouds_warp_scale = 6.0; // domain-warp frequency; keep scale*strength under ~0.08
uniform float clouds_warp_strength = 0.01; // domain-warp amount, in uv units
uniform float clouds_detail_scale = 90.0; // sub-texel detail frequency
uniform float clouds_detail_strength = 0.45; // how hard detail erodes/extends coverage
uniform float clouds_detail_floor = 0.04; // coverage below which sky stays clear
uniform float clouds_edge_gamma = 1.0; // alpha-falloff shaping: >1 softens/thins the fringe, <1 hardens it

// Affine range unpacking for a range-tagged albedo (IVAssetPreloader.parse_range_tags),
// mirroring surface.gdshader. A tagged file stores (physical - lo) / (hi - lo), so an
// overlay deck spends all 256 codes on the reflectance its features actually have instead
// of on the [0,1] they do not, and can carry a channel past 1.0 that an untagged sRGB file
// cannot hold at all. Defaults are the identity, so an untagged map renders as before.
// Applied BEFORE clouds_color, which is a tint on physical reflectance.
uniform vec3 albedo_range_lo = vec3(0.0);
uniform vec3 albedo_range_hi = vec3(1.0);

// Disc photometry (see _photometry.gdshaderinc). A deck MUST carry the same law as the
// surface it covers: this shell reproduces its body's map only through the alpha blend
// A*C + (1-A)*S, and two different laws break that identity everywhere except the
// subsolar point - progressively toward the limb, where the mismatch reaches tens of
// percent and every feature reads as a dark smear. Set both columns from the surface
// shell's own values whenever that shell sets either. Each is an exact no-op at its
// default, so a deck over a Lambert surface (Earth) needs neither.
uniform float minnaert_k : hint_range(1.0, 2.0) = 1.0;
uniform float lunar_lambert : hint_range(0.0, 1.0) = 0.0;

const int OCTAVES = 5;

// Noise rides model space (not uv or screen space) so detail spins with the deck
// — the shell rotates via its _rotate process — and a sphere has no seam or pole
// pinch here that a uv- or lat/long-based field would show.
varying vec3 model_position;
varying vec3 v_world_position; // true world position; VERTEX is farwarp-remapped
varying vec3 v_camera_local;   // the camera in this shell's local frame, for atm_disc_air()
varying vec3 v_sun_local;      // the sun direction in that frame, unit
varying flat float v_far_floor; // atm_far_floor() is uniform-only: per vertex, not per fragment
varying flat float v_disc_weight; // disc/point crossfade; 1 resolved, 0 fully handed off

// Disc/point handoff, set each frame by IVShellsModel's disc LOD from IVBody.psf_handoff.
// Every shell of a body fades together, on the body's mean radius rather than this shell's
// scaled one: an overlay left drawn over a handed-off point would be the whole body's
// silhouette in cloud. The defaults saturate the ramp fully ON, so a body with no
// IVBodyPSF renders exactly as it did before this existed.
uniform float angular_radius = 0.0; // body mean radius / camera distance
uniform float handoff_low = -2.0;   // px on-screen radius at/below which the quad replaces this
uniform float handoff_high = -1.0;  // px at/above which this shell fully replaces the quad's core



void vertex() {
	model_position = VERTEX; // unit-sphere local position (captured before farwarp overwrites VERTEX)
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (atm_present()) {
		// The ray geometry for atm_disc_air() runs in the shell's own frame, where the
		// (oblate) shell is the unit sphere; see atmosphere_limb.gdshader. Skipped on an
		// airless body, whose varyings then go unread.
		mat4 inverse_model = inverse(MODEL_MATRIX);
		v_camera_local = (inverse_model * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
		v_sun_local = normalize(mat3(inverse_model) * sun_direction);
		v_far_floor = atm_far_floor();
	}
	farwarp_lit_vertex(MODELVIEW_MATRIX, MODELVIEW_NORMAL_MATRIX, VERTEX, NORMAL);
	v_disc_weight = body_disc_weight(body_pixel_radius(angular_radius,
			PROJECTION_MATRIX[1][1], VIEWPORT_SIZE.y), handoff_low, handoff_high);
}


void fragment() {
	vec3 noise_position = normalize(model_position);

	// Warp the lookup to give cloud edges organic, non-repeating wander. (The bicubic
	// fetch below is what removes the texel squares; this only adds drift.) A vector warp
	// folds the texture onto itself once its Jacobian exceeds 1, printing bright caustic
	// ridgelines that cross in "X" cusps along the edges — so keep it gentle: one smooth
	// (quintic) octave, with clouds_warp_scale * clouds_warp_strength held under ~0.08.
	vec2 warp = vec2(value_noise(noise_position * clouds_warp_scale),
			value_noise(noise_position * clouds_warp_scale + vec3(19.7))) - vec2(0.5);
	vec4 cloud = texture_bicubic(albedo, UV + warp * clouds_warp_strength);
	float base_coverage = cloud.a;

	// Gate detail by base coverage so clear sky stays clear and detail concentrates
	// in and at the edges of clouds.
	float gate = smoothstep(0.0, clouds_detail_floor + 0.15, base_coverage);
	float detail = fbm(noise_position * clouds_detail_scale, OCTAVES) - 0.5;
	float coverage = clamp(base_coverage + detail * clouds_detail_strength * gate, 0.0, 1.0);

	// Decoded on the way in and encoded on the way out (see _display.gdshaderinc), so every
	// colour term between the two is a linear reflectance -- which is what a range tag, a
	// disc law and an atmosphere's transmittance all state.
	ALBEDO = display_decode(clouds_color) * (albedo_range_lo
			+ (albedo_range_hi - albedo_range_lo) * display_decode(cloud.rgb));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// Shape the alpha rolloff at the boundary. The base map's edge is a straight bilinear
	// ramp one (kilometers-wide) texel across, which reads as fake up close; the gamma
	// curve bends it into a softer, more cloud-like falloff. Default 1.0 leaves it linear.
	ALPHA = pow(coverage, clouds_edge_gamma) * clouds_opacity;

	// Rebuilt ambient (engine ambient is disabled; see render_mode). Added before
	// the shadow so occlusion removes sunlight, not starlight; see the include.
	// Kept for the twilight term below, which is DIFFUSE light and so takes the
	// unfactored albedo, exactly as the isotropic ambient on the next line does.
	vec3 unlit_albedo = ALBEDO;
	EMISSION += ALBEDO * ambient_light; // the feed already carries exposure; see the include

	// Disc photometry, AFTER the isotropic ambient above (which takes the unfactored
	// albedo) and independent of the shadow multiply below. This shader never writes
	// NORMAL, so the interpolated macroscopic normal is what is wanted and what is here.
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
	// twilight glow past the terminator), composited here rather than blended by the limb
	// shell — in the fragment the sum runs in linear light on every renderer, where the
	// blend does not (THE COMPOSITING SPLIT in the include). This deck fragment traces
	// its own ray down to the disc, so the veil it adds is the veil the surface fragment
	// behind it adds, and the mix passes it through at weight alpha + (1 - alpha) = 1.
	// Skipped at coverage exactly zero: a mix at alpha 0 keeps the destination, so the
	// quadrature's result could never reach the frame. The luma is what the limb's alpha
	// used to remove from everything behind it — lit albedo, the emission terms above,
	// and the specular lobe as its square root.
	vec3 atm_path = vec3(0.0);
	float atm_behind_luma = 1.0;
	if (ALPHA > 0.0) {
		atm_disc_air(v_camera_local, model_position, v_sun_local, sun_angular_radius,
				v_far_floor, atm_path, atm_behind_luma);
	}
	ALBEDO *= atm_behind_luma;
	SPECULAR *= sqrt(atm_behind_luma);
	EMISSION = EMISSION * atm_behind_luma + atm_path * sun_light_energy;

	// Specular keeps the silhouette fade rather than coverage (see limb_mean_incidence).
	SPECULAR *= sqrt(limb_specular_fade);

	ALBEDO = display_write_albedo(ALBEDO);
	EMISSION = display_write(EMISSION);
	// Alpha-blended, so the one weight fades everything this shell contributes -- and the
	// pixel's coverage by this shell rides the same alpha, which is where it belongs.
	ALPHA *= v_disc_weight * limb_fade;
}
