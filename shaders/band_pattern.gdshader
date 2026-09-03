// band_pattern.gdshader
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

// A banded atmosphere as a TEXTURELESS surface: zonal bands, longitudinal streaks, a
// planetary wave and true color, all from the uniforms below. Name it in a shells.tsv
// "shader" column on a shell-0 row; the body then ships no surface map. It binds no
// channels, so there is no cubemap variant and none is needed.
//
// Suits a smooth, mostly zonal cloud deck (Venus, Titan, Uranus, Neptune). NOT for Jupiter
// or Saturn, whose named features — the Great Red Spot, the polar hexagon — no parameter
// set reproduces. Where a body has features that are not zonal, put them in an overlay
// shell instead; Neptune does this for its Great Dark Spot and clouds.
//
// ALBEDO = albedo_color * (1 + band_contrast * pattern), in linear light.
//
// THREE THINGS TO GET RIGHT:
//   - Band amplitudes must be zero-mean over the sphere (cos-weighted), or band_contrast
//     moves the body's brightness as well as its contrast.
//   - Band latitudes are PLANETOGRAPHIC; set polar_equatorial_ratio on an oblate body.
//   - Past a body's contrast headroom the band tops flatten (see albedo_color).

#include "_detail.gdshaderinc"       // value_noise, fbm
#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_photometry.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"
#include "_atmosphere.gdshaderinc"
#include "_point_spread_function.gdshaderinc" // body_pixel_radius / body_disc_weight (the handoff)


// ----- color and level -----
// The body's true color at its MEAN level: the mu = mu0 = 1 value, since the engine
// applies its own N.L. Its brightest channel sets the contrast headroom — the
// band_contrast at which that channel reaches albedo 1 and the bands stop gaining
// contrast. Venus 1.40, Neptune 2.67, Titan 4.43, Uranus 22.2.
uniform vec4 albedo_color : source_color = vec4(1.0);

// A second color the pattern's DARK end leans toward, for a body whose belts or polar hood
// differ in hue as well as level. Give albedo_color the bright side's hue and this the dark
// side's, at equal luminance, so the tint moves hue only.
uniform vec4 band_tint_color : source_color = vec4(1.0);
// Reciprocal of the pattern magnitude at which the tint saturates, so a few-percent pattern
// needs a strength in the TENS. 0 disables; 1.0 on a 3 % pattern is a 3 % mix, i.e. nothing.
uniform float band_tint_strength = 0.0;


// ----- zonal profile -----
// Six gaussian belts, each vec3(centre_deg, width_deg, amplitude). Amplitude is a signed
// fraction of the mean level: +0.20 is a zone 20 % brighter, -0.15 a belt 15 % darker.
// Width <= 0 disables a slot. A polar cap is a belt centred at +/-90.
uniform vec3 band0 = vec3(0.0, 0.0, 0.0);
uniform vec3 band1 = vec3(0.0, 0.0, 0.0);
uniform vec3 band2 = vec3(0.0, 0.0, 0.0);
uniform vec3 band3 = vec3(0.0, 0.0, 0.0);
uniform vec3 band4 = vec3(0.0, 0.0, 0.0);
uniform vec3 band5 = vec3(0.0, 0.0, 0.0);

// A hemispheric step: vec3(boundary_deg, transition_width_deg, north_minus_south). Use for
// an asymmetry with a boundary; gaussians can only spread one across the whole globe.
uniform vec3 band_step = vec3(0.0, 0.0, 0.0);

// Scales bands, streaks and wave together. 0 renders the body flat in its true color.
uniform float band_contrast = 1.0;


// ----- longitudinal structure -----
// Zonal streaks. They decorrelate over about 57 / (streak_scale * streak_squash) DEGREES
// of latitude — keep that coarser than the narrowest band they sit inside, or the fine
// term dominates what should be background texture.
uniform float streak_strength = 0.0;  // 0 disables; fraction of the mean level, peak to peak
uniform float streak_scale = 8.0;     // base frequency
uniform float streak_squash = 6.0;    // latitudinal squash; higher = thinner, more drawn out
// Spiral shear in degrees at the pole, antisymmetric across the equator, so streaks converge
// toward both poles. Also shears the band-edge turbulence below.
uniform float streak_tilt = 0.0;
// Concentrates streaks into the dark parts of the zonal profile: gate = exp(-gate * zonal).
// 0 is an exact no-op; positive favours belts over zones, negative the reverse.
uniform float streak_gate = 0.0;

// Wanders the band edges, in degrees of latitude. Squash > 1 elongates the warp field along
// the streak_tilt flow, giving long diagonal excursions rather than a uniform ripple.
uniform float band_turbulence = 0.0;  // 0 disables
uniform float band_turbulence_scale = 3.0;
uniform float band_turbulence_squash = 1.0;

// A large-scale planetary wave (Venus' Y feature). wave_tilt shears the crests with
// latitude, which is what bends the equatorial bar into the Y.
uniform float wave_amplitude = 0.0;   // 0 disables
uniform float wave_number = 1.0;      // 1 gives one crest and one trough around the body
uniform float wave_tilt = 0.0;        // degrees of crest sweep, per hemisphere


// ----- figure and material -----
// Polar / equatorial radius (b/a), so band latitudes are read as planetographic. 1.0 is an
// exact no-op. Worth 0.67 deg on Uranus, 0.50 on Neptune; Venus and Titan are spherical.
uniform float polar_equatorial_ratio = 1.0;
uniform float roughness_scale = 1.0;
uniform float metallic = 0.0;
uniform float metallic_specular = 0.5; // dielectric specular; 0.5 = StandardMaterial3D default
// Minnaert k (see _photometry.gdshaderinc): 1.0 = Lambert, the exact-no-op default; above
// 1.0 darkens the limb, which is the direction a cloud deck needs. Set per body in
// shells.tsv. Values below 1.0 are the other direction and are ignored here.
uniform float minnaert_k : hint_range(1.0, 2.0) = 1.0;
// Lunar-Lambert L, the k < 1 direction Minnaert cannot serve (see _photometry.gdshaderinc):
// 0.0 = Lambert, the exact-no-op default. A body sets one law or the other, never both;
// both factors are applied because each is an identity at its own default.
uniform float lunar_lambert : hint_range(0.0, 1.0) = 0.0;
// Reflectance ceiling the band tops are scaled under; see fragment(). 1.0 is the storage
// convention, not a physical bound - raise it for a body whose own reflectance exceeds it.
uniform float albedo_ceiling = 1.0;
// Physical reflectance per unit of albedo_color; see fragment(). 1.0 for any body whose
// reflectance fits in a Color.
uniform float albedo_scale = 1.0;


// ----- the shipped bodies -----
// What each of the four uses, as a starting point for tuning. Full values are in shells.tsv.
//
// VENUS   Four belts: a broad dark equatorial band and bright polar collars. Streaks are
//         gated and sheared 70 deg into mid-latitude chevrons, with heavy low-frequency
//         band_turbulence (22 deg, squash 3) for the sweeping non-horizontal distortion the
//         UV mosaics show, plus a wavenumber-1 wave for the Y feature.
//         band_contrast 1.0 ships and is 6x real visible cloud contrast; 0.167 is
//         photometrically true and nearly featureless, which is what Venus actually is.
//         Headroom is 1.40, so above that the bright poles stop gaining contrast.
// TITAN   Almost flat. A band_step of -6 % across 8 deg at the equator carries the
//         north-south asymmetry, one belt gives the north polar hood, and band_tint_color
//         (strength 30) makes the northern hemisphere browner as well as darker.
// URANUS  Two faint rings at +/-54 deg, +2.6 % — the whole of its measured zonal signal.
//         Streaks are at its measured longitudinal level and near-invisible by design.
//         Raise band_contrast rather than the amplitudes if it should read more strongly.
// NEPTUNE Six belts: bright mid-north, broad dark north, dark south, bright polar caps.
//         Streaks are gated hard (5.0) into the dark belts. Its discrete features are a
//         separate cloud shell, not this shader.

const int STREAK_OCTAVES = 4;
const int TURBULENCE_OCTAVES = 3;

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


varying vec3 model_position;   // unit-sphere local position; the pattern's only input
varying vec3 v_world_position; // true world position; VERTEX is farwarp-remapped
varying vec3 v_camera_local;   // the camera in this shell's local frame, for atm_disc_air()
varying vec3 v_sun_local;      // the sun direction in that frame, unit
varying flat float v_far_floor; // atm_far_floor() is uniform-only: per vertex, not per fragment
varying flat float v_disc_weight; // disc/point trade; >0 draw, 0 handed off (a step here)


float gaussian_band(float latitude_deg, vec3 band) {
	if (band.y <= 0.0) {
		return 0.0; // an unused slot, not a zero-width spike
	}
	float t = (latitude_deg - band.x) / band.y;
	return band.z * exp(-0.5 * t * t);
}


// Centred so it contributes +/- half its amplitude, i.e. stays zero-mean for a boundary
// on the equator.
float hemisphere_step(float latitude_deg, vec3 step_params) {
	if (step_params.y <= 0.0) {
		return 0.0;
	}
	float t = clamp((latitude_deg - step_params.x) / step_params.y * 0.5 + 0.5, 0.0, 1.0);
	return step_params.z * (t * t * (3.0 - 2.0 * t) - 0.5);
}


// Rotation about the polar axis growing with sin(latitude). Shared by the streaks and the
// band-edge turbulence so the two ride one flow.
vec3 shear_about_axis(vec3 dir, float tilt_deg) {
	float shear = radians(tilt_deg) * dir.y;
	float cs = cos(shear);
	float sn = sin(shear);
	return vec3(cs * dir.x - sn * dir.z, dir.y, sn * dir.x + cs * dir.z);
}


void vertex() {
	model_position = VERTEX; // captured before farwarp overwrites VERTEX
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
	// No normal map, so the smooth sphere normal farwarp sets is the final one.
	farwarp_lit_vertex(MODELVIEW_MATRIX, MODELVIEW_NORMAL_MATRIX, VERTEX, NORMAL);
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
	vec3 dir = normalize(model_position);
	float rho = length(dir.xz);

	// Two-argument form is well conditioned at the poles, where rho -> 0.
	float latitude_deg = degrees(atan(dir.y, rho * polar_equatorial_ratio));

	if (band_turbulence != 0.0) {
		vec3 warp_dir = shear_about_axis(dir, streak_tilt);
		warp_dir = vec3(warp_dir.x, warp_dir.y * band_turbulence_squash, warp_dir.z);
		latitude_deg += (fbm(warp_dir * band_turbulence_scale, TURBULENCE_OCTAVES) - 0.5)
				* 2.0 * band_turbulence;
	}

	float zonal = gaussian_band(latitude_deg, band0)
			+ gaussian_band(latitude_deg, band1)
			+ gaussian_band(latitude_deg, band2)
			+ gaussian_band(latitude_deg, band3)
			+ gaussian_band(latitude_deg, band4)
			+ gaussian_band(latitude_deg, band5)
			+ hemisphere_step(latitude_deg, band_step);
	float pattern = zonal;

	if (streak_strength != 0.0) {
		vec3 sheared = shear_about_axis(dir, streak_tilt);
		vec3 noise_position = vec3(sheared.x, sheared.y * streak_squash, sheared.z)
				* streak_scale;
		float gate = exp(-streak_gate * zonal);
		pattern += (fbm(noise_position, STREAK_OCTAVES) - 0.5) * streak_strength * gate;
	}

	if (wave_amplitude != 0.0) {
		float longitude = atan(dir.x, dir.z);
		// Fade at the poles, where longitude is meaningless and a crest would spike.
		pattern += wave_amplitude * rho * rho
				* cos(wave_number * longitude + radians(wave_tilt) * dir.y);
	}

	pattern *= band_contrast;

	// Decoded here and encoded at the end of fragment() (see _display.gdshaderinc): the tint
	// mix, albedo_scale, the pattern and the ceiling all state linear reflectance, and none
	// of them means anything applied to a display-referred colour.
	vec3 base = display_decode(albedo_color.rgb);
	if (band_tint_strength != 0.0) {
		base = mix(base, display_decode(band_tint_color.rgb),
				clamp(-pattern * band_tint_strength, 0.0, 1.0));
	}
	// albedo_color and band_tint_color are sRGB Colors, so neither can carry a channel
	// above 1.0 - the conversion clamps there. A body whose physical reflectance exceeds
	// that (Venus needs 1.27 to reach its geometric albedo; see albedo_ceiling) carries
	// the excess here instead. Applied to base, after the tint mix, so it scales both
	// endpoints alike and leaves the pattern and the tint blend untouched.
	base *= albedo_scale;
	vec3 color = max(base * (1.0 + pattern), vec3(0.0));

	// Ceiling by scaling the whole vector: a per-channel clamp would clip the strongest
	// channel first and drag the color toward white where the pattern is brightest. This
	// holds chromaticity exactly and flattens the band tops instead. The ceiling is a
	// uniform because 1.0 is a storage limit, not a physical one, and a body can sit above
	// it: reaching geometric albedo p under a law whose disc integrates to F of the
	// subsolar level needs p/F, and Venus at p = 0.689 needs 1.27. Nothing downstream
	// clamps ALBEDO, so the only cost of raising it is this shader's own band tops.
	float peak = max(color.r, max(color.g, color.b));
	ALBEDO = peak > albedo_ceiling ? color * (albedo_ceiling / peak) : color;

	ROUGHNESS = clamp(roughness_scale, 0.0, 1.0);
	METALLIC = metallic;
	SPECULAR = metallic_specular;

	// Rebuilt ambient (engine ambient is disabled; see render_mode). Added before the
	// shadow so occlusion removes sunlight, not starlight; see the include.
	// Kept for the twilight term below, which is DIFFUSE light and so takes the
	// unfactored albedo, exactly as the isotropic ambient on the next line does.
	vec3 unlit_albedo = ALBEDO;
	EMISSION = ALBEDO * ambient_light; // the feed already carries exposure; see the include

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
