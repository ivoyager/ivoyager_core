// atmosphere_limb.gdshader
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
// blend_premul_alpha: the fragment's colour is added and what lies behind is kept by
// (1 - ALPHA); see below. skip_vertex_transform: the farwarp vertex remap.
render_mode blend_premul_alpha, ambient_light_disabled, shadows_disabled, skip_vertex_transform;

// A body's atmosphere, drawn on an IVShellsModel overlay shell that encloses it (Earth's at
// scale 1.02, Titan's at 1.20). Name it in the shell's shells.tsv "shader" column; the row's
// atm_* columns are the atmosphere (see _atmosphere.gdshaderinc for every one of them and
// for the model), and IVShellsModel propagates them to the body's surface and cloud shells,
// which take their sunlight through the same air.
//
// WHAT IT DRAWS. Single scattering of sunlight along the view ray through the atmosphere:
// the thin bright band beyond the limb (Earth's blue band from orbit, Titan's stacked haze
// shells), the veil in front of the disc that fades it toward the edge, the twilight
// stratification where the sun's grazing light reddens, the forward-scattered ring and the
// cusps that reach round a backlit crescent. All from one integral and one set of physical
// parameters; nothing is a phase-function pastiche. Its output is I/F, so it rides the
// sun's light_energy exactly like the surface beneath it, exposure and all, and meters
// with it (IVExposureManager's limb candidate).
//
// HOW IT COMPOSITES. Per fragment the include returns the path radiance and the
// transmittance of whatever lies behind the ray. With blend_premul_alpha the engine forms
// src.rgb + dst.rgb * (1 - src.a), so ALBEDO is the radiance as-is and ALPHA is one minus
// the transmittance's luma; the chromatic part of that transmittance is applied by the
// surface and cloud shaders themselves (atm_view_tint), which is exact and lets a cloud
// deck escape the air below it. Where the air is thin, alpha is ~0 and nothing darkens.
// The shell renders its front faces only, so every pixel gets exactly one fragment whose
// whole ray - both halves of a beyond-limb ray - the include integrates.
//
// LIGHTING. A custom light() adds LIGHT_COLOR * ATTENUATION / PI; the engine multiplies by
// ALBEDO afterwards, and LIGHT_COLOR carries a factor PI, so the rendered value is
// I/F * light_energy - the surface convention - and the terminator is the sun's, through
// sun_direction fed by IVSunOcclusionManager (this material declares the occluder block by
// including _sun_occlusion.gdshaderinc, which is how the manager finds it).
//
// TASTE. Physical parameters ARE the look. With physical light off, atm_intensity and
// atm_thickness act as by-eye multipliers; the iv_limb_scale global (1.0 then, 0.0 under
// physical light) gates them to exactly 1.0 while the physical model runs.

#include "_farwarp.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"
#include "_atmosphere.gdshaderinc"

varying vec3 model_position; // unit-sphere local position (captured before farwarp overwrites VERTEX)
varying vec3 v_camera_local; // the camera in this shell's local frame; the same at every vertex
varying vec3 v_sun_local;    // the sun direction in that frame, unit; the same at every vertex
varying flat float v_far_floor; // atm_far_floor() is uniform-only: per vertex, not per fragment


void vertex() {
	model_position = VERTEX;
	// The geometry runs in the shell's own frame, where the (oblate) shell is the unit sphere
	// and altitude is exact. The camera is origin-shifted to the world origin each frame, so
	// this stays well inside float32 at any zoom.
	mat4 inverse_model = inverse(MODEL_MATRIX);
	v_camera_local = (inverse_model * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	v_sun_local = normalize(mat3(inverse_model) * sun_direction);
	v_far_floor = atm_far_floor();
	farwarp_lit_vertex(MODELVIEW_MATRIX, MODELVIEW_NORMAL_MATRIX, VERTEX, NORMAL);
}


void fragment() {
	vec3 path;
	vec3 transmittance;
	atm_limb(v_camera_local, model_position, normalize(v_sun_local), sun_angular_radius,
			v_far_floor, path, transmittance);
	ALBEDO = path;
	ALPHA = clamp(1.0 - atm_luma(transmittance), 0.0, 1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}


void light() {
	// The engine multiplies DIFFUSE_LIGHT by ALBEDO after this; /PI undoes the PI in
	// LIGHT_COLOR so the result is I/F * light_energy, as for a surface.
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION / ATM_PI;
}
