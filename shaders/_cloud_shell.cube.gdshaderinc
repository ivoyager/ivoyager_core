// _cloud_shell.cube.gdshaderinc
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
// See _cloud_shell.gdshaderinc for what each mode is for; this variant changes only how the
// cloud map is sampled.
render_mode skip_vertex_transform, ambient_light_disabled;

// Cubemap counterpart of cloud_shell.gdshader: the same lit, translucent deck, but the
// cloud map is sampled by DIRECTION from a Cubemap instead of by UV from an equirect map,
// which removes the pole starburst and the +/-180 seam. IVAssetPreloader routes a shell here
// automatically when its discovered channels are Cubemaps (cube_shader_variants); the tables
// are unchanged.
//
// The map's coverage lives in ALPHA, so the strip must be baked and imported
// alpha-preserving or the deck renders as a solid shell — see bake_cubemap.py
// load_equirect() and IVCubeStripSaver. Its rgb is the deck's own reflectance: a near
// neutral grey where the deck can only add brightness (Earth), each feature's own colour
// where the deck holds features darker than what they cover (Neptune). What that pair MEANS
// is set by clouds_two_stream_map below, which is where a deck built from a separated
// coverage and thickness parts company with one built from a single channel.
//
// Every uniform here means what it means in _cloud_shell.gdshaderinc, so a body's shells.tsv
// tuning carries over unchanged when its maps are swapped for cubemaps. Keep it that way:
// the two are meant to be the same deck sampled two ways.

#include "_detail.gdshaderinc"       // cubic_weights, for the cube bicubic
#include "_detail.cube.gdshaderinc"  // texture_bicubic_cube
#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_photometry.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"
#include "_atmosphere.gdshaderinc"
#include "_point_spread_function.gdshaderinc" // body_pixel_radius / body_disc_weight (the handoff)

uniform samplerCube albedo : source_color; // auto-bound: <prefix>.<file_tag>.albedo.*
uniform vec3 clouds_color : source_color = vec3(1.0); // tint over the map's own rgb
uniform float clouds_opacity = 1.0; // overall coverage multiplier
// The map's alpha is a geometric cloud FRACTION and its rgb the cloud's own conservative
// two-stream albedo R = tau* / (tau* + 1), rather than the composited opacity/reflectance
// pair a ONE-CHANNEL source can only produce. Two independent numbers is what tells a texel
// half covered by opaque cloud from one fully covered by thin cloud, and those behave
// differently at every sun angle: the first passes full sunlight through its clear half at
// any incidence, the second passes exp(-tau/mu0) through all of it and shuts off as the sun
// grazes. Earth's deck is built this way from MODIS cloud fraction and cloud optical
// thickness (build_earth_clouds.py in the assets build tree); Neptune's, whose source is one
// channel, is not. Off, the map's channels are already composited and go straight through,
// which is what every deck built before 2026-09-08 holds. IMPORTANT: Flag changes to how this
// pair is decoded, or to the reference cosine 1/2 that R is stored and inverted at, so they
// can be mirrored in the asset build pipeline (a separate private repository).
uniform bool clouds_two_stream_map = false;
// The deck's lit cross-section per unit horizontal ground as the sun goes down. A
// plane-parallel layer says mu0 and a real cloud field says more: at grazing incidence what
// the sun lights is the SIDES of the cloud, whose area per unit ground is the field's relief
// over its spacing. 0 is the plane-parallel layer and an exact no-op. This term alone carries
// a deck past its body's own terminator, where it stays geometrically sunlit out to
// mu0 = -sqrt(1 - (surface_scale/shell_scale)^2) -- 3.2 deg past the ground's on Earth --
// graded to nothing across that band as the deck's own height enters the shadow. Nothing here
// measures it; it is an appearance judgment. See PHOTOMETRIC_MODEL.md.
uniform float clouds_relief : hint_range(0.0, 0.5) = 0.0;

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

// Numeric floors for the two-stream unpack, each far below anything a rendered deck resolves.
const float CLOUD_MIN_TRANSMITTANCE = 1.0e-4; // caps tau* near 1e4, i.e. optically infinite
const float CLOUD_MIN_COSINE = 1.0e-3;        // the grazing limit R(mu) -> 1 approaches
const float CLOUD_MIN_OPACITY = 1.0e-5;       // keeps ALBEDO = R / hides finite as tau* -> 0

varying vec3 model_position; // unit-sphere local position, for the map lookup and atm_disc_air()
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
	vec4 cloud = texture_bicubic_cube(albedo, normalize(model_position));
	float coverage = cloud.a;

	// This shader never writes NORMAL, so the interpolated macroscopic normal is what is
	// wanted. The two cosines are formed here rather than with the other atmosphere terms
	// below because a deck whose map keeps coverage and thickness apart composites through
	// both of them (clouds_two_stream_map).
	vec3 macro_normal = normalize(NORMAL);
	vec3 sun_view = normalize(mat3(VIEW_MATRIX) * sun_direction);
	float atm_mu0 = dot(macro_normal, sun_view);
	float atm_mu = dot(macro_normal, VIEW);

	// Decoded on the way in and encoded on the way out (see _display.gdshaderinc), so every
	// colour term between the two is a linear reflectance -- which is what a range tag, a
	// disc law and an atmosphere's transmittance all state.
	vec3 map_reflectance = albedo_range_lo
			+ (albedo_range_hi - albedo_range_lo) * display_decode(cloud.rgb);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	coverage *= clouds_opacity;
	vec3 sky_albedo; // what the deck returns to light arriving from no particular direction
	if (clouds_two_stream_map) {
		// THE LAYER LAW AND THE GRADED SHADOW. The map's two channels are independent here
		// (see the uniform), so what the alpha blend needs is formed FROM them at this
		// fragment's own geometry rather than read off. rgb carries the scaled optical depth
		// as the conservative two-stream albedo at mu = 1/2, so tau* = R / (1 - R); that
		// reference is fixed at 1/2 for exactly this inverse and the build script must agree.
		// A texel is then `coverage` of cloud of that depth plus `1 - coverage` of clear sky,
		// and each of the light's two legs takes ITS OWN cosine:
		//
		//     R(mu) = tau* / (tau* + 2 mu)      reflected
		//     T(mu) = 1 - R(mu)                 transmitted, direct plus diffuse
		//
		// Matching ALPHA * ALBEDO + (1 - ALPHA) * surface against
		// f (R(mu0) + surface T(mu0) T(mu)) + (1 - f) surface gives the three lines below.
		// What that buys is the whole point of keeping the channels apart: the clear fraction
		// passes FULL sunlight at any incidence while the covered fraction's sun leg goes as
		// T(mu0) and shuts off as the sun grazes -- the shadow graded through the deck's own
		// thickness instead of cut at a line. At the encoding's own mu0 = mu = 1/2 every line
		// returns exactly what a composited (opacity, reflectance) pair held.
		float reflect = clamp(atm_luma(map_reflectance), 0.0, 1.0);
		float tau_star = reflect / max(1.0 - reflect, CLOUD_MIN_TRANSMITTANCE);
		float sun_cos = max(atm_mu0, 0.0);
		float view_cos = max(atm_mu, CLOUD_MIN_COSINE);
		float sun_through = 2.0 * sun_cos / (tau_star + 2.0 * sun_cos);
		float view_through = 2.0 * view_cos / (tau_star + 2.0 * view_cos);
		// What the deck hides from the CAMERA, which is its view leg alone. The sun leg is
		// not missing: it moved to clouds_sun_transmittance(), which puts it on the surface at the
		// place the deck's shadow actually falls rather than directly underneath -- so the
		// two together still remove `1 - T(mu0) T(mu)` of the surface's light, and a viewer
		// can now see where it went. Keeping it here as well would count it twice.
		float hides = max(1.0 - view_through, CLOUD_MIN_OPACITY);
		vec3 tint = display_decode(clouds_color) * (map_reflectance / max(reflect, 1.0e-4));
		// The BEAM takes R at the sun's own cosine; the sky takes the encoding's reference,
		// because R(mu0) is an answer about one incidence angle and light off the whole sky
		// has none. Dividing by `hides` is what the blend undoes, so ALPHA * ALBEDO comes to
		// coverage * R(mu0) exactly and the deck's own light needs no other correction.
		ALBEDO = tint * (tau_star / (tau_star + 2.0 * max(sun_cos, CLOUD_MIN_COSINE)) / hides);
		sky_albedo = tint * (reflect / hides);
		ALPHA = coverage * hides;
	} else {
		ALBEDO = display_decode(clouds_color) * map_reflectance;
		sky_albedo = ALBEDO;
		ALPHA = coverage;
	}

	// Rebuilt ambient (engine ambient is disabled; see render_mode). Added before
	// the shadow so occlusion removes sunlight, not starlight; see the include.
	// Kept for the twilight term below, which is DIFFUSE light and so takes the
	// unfactored albedo, exactly as the isotropic ambient on the next line does.
	vec3 unlit_albedo = sky_albedo;
	vec3 beam_albedo = ALBEDO; // the same thing on an unsplit map; direct light wants this one
	EMISSION += sky_albedo * ambient_light; // the feed already carries exposure; see the include

	// Disc photometry, AFTER the isotropic ambient above (which takes the unfactored
	// albedo) and independent of the shadow multiply below.
	float atm_beam_response = minnaert_albedo_factor(macro_normal, sun_view, VIEW, minnaert_k)
			* lunar_lambert_albedo_factor(macro_normal, sun_view, VIEW, lunar_lambert);
	ALBEDO *= atm_beam_response;
	// The body's atmosphere above this shell (the limb row's atm_* columns, propagated
	// here; an exact no-op without them): direct light reddened along the sun path, and
	// the chromatic half of the view-path extinction whose luma the atm_disc_air() block
	// below removes. See _atmosphere.gdshaderinc.
	vec3 atm_tint;
	vec3 atm_sun_t;
	vec3 atm_diffuse;
	atm_receiver_light(atm_mu, atm_mu0, atm_tint, atm_sun_t, atm_diffuse);
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
	EMISSION += unlit_albedo * atm_sky_excess(atm_mu0, atm_diffuse, atm_sky_response,
			atm_beam_response) * atm_tint * (sun_light_energy * sun_visible);
	// The share of the pixel's mean sun angle the engine's own N.L cannot deliver, because at
	// this pixel that N.L is zero (see limb_mean_incidence). Direct sunlight, so it takes the
	// beam response, the sun path's transmittance and the tint exactly as the lit albedo did.
	EMISSION += beam_albedo * atm_beam_response * atm_sun_t * atm_tint * limb_emission_mu0
			* (sun_light_energy * sun_visible);
	// THE DECK'S OWN TERMINATOR. A plane-parallel layer takes F mu0 and so goes dark at
	// mu0 = 0 however thick it is -- right for the ground, which IS a horizontal surface, and
	// wrong for a cloud field, whose sides are what a low sun lights. `clouds_relief` is that
	// side area per unit ground; sqrt(mu0^2 + relief^2) reaches it smoothly and is worth under
	// 2 % of the disc wherever mu0 exceeds it. The deck also stands above the disc, so it
	// stays geometrically sunlit past the GROUND's terminator out to
	// mu0 = -sqrt(1 - (surface/shell)^2), and enters that shadow across its own height rather
	// than at a line -- the same lit-height grading the limb exposure ceiling uses, and it
	// needs nothing but the two radii the table already carries. EMISSION because the engine's
	// N.L threw this light away, and the ISOTROPIC response because light on a vertical face
	// is not light at the layer's own incidence.
	if (clouds_relief > 0.0 && shell_scale > surface_scale) {
		float shadow_mu0 = -sqrt(max(1.0 - (surface_scale * surface_scale)
				/ (shell_scale * shell_scale), 0.0));
		float lit_height = clamp((atm_mu0 - shadow_mu0) / max(-shadow_mu0, 1.0e-6), 0.0, 1.0);
		float beam_mu0 = max(atm_mu0, 0.0);
		float cross_section = sqrt(beam_mu0 * beam_mu0 + clouds_relief * clouds_relief)
				* lit_height;
		EMISSION += sky_albedo * atm_sky_response * atm_sun_t * atm_tint
				* max(cross_section - beam_mu0, 0.0) * (sun_light_energy * sun_visible);
	}

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
