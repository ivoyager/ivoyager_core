// equirect_to_cube.gdshader
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
shader_type canvas_item;
// blend_disabled so COLOR reaches the framebuffer verbatim, with no compositing.
render_mode unshaded, blend_disabled;

// Reprojects an equirectangular body map into a 3x2 cube-face strip in one draw, for
// IVMapConverter (Project > Tools > "Map Convert..."). This is the in-editor counterpart
// of bake_cubemap.py in the tools submodule, and the two must produce equivalent output --
// so every convention below is pinned to that script rather than chosen here, and a change
// to either belongs in both.
//
// There is deliberately no source_color hint and no sRGB conversion anywhere: the Python
// baker averages raw 8-bit values, so a decode/encode round trip would shift every output
// away from it. The viewport must likewise keep use_hdr_2d off, which costs 1 LSB.

// Sampled with texelFetch only, so no sampler state applies -- the hints just document
// that. Hardware bilinear is deliberately NOT used: its subtexel weight precision is
// limited, which showed up as errors proportional to local contrast (a mean |error| of
// ~0.5/255 overall but excursions past 5 wherever the map has sharp features).
uniform sampler2D source : filter_nearest, repeat_disable;
uniform vec2 source_size = vec2(1.0); // equirect pixels; sampling depends on both axes
uniform float face_size = 1.0;        // output cube face edge, in pixels
uniform int supersample = 4;          // NxN taps per output texel, area-averaged
uniform bool object_space_normal = false;
// Half-range the normal residual is encoded over; must match both the baker's
// --normal-residual-scale and spheroid_surface.cube.gdshader's uniform of that name.
uniform float normal_residual_scale = 1.0;


// Godot cube face order X+ X- Y+ Y- Z+ Z- with the standard GL per-face (sc, tc) axes.
// The same table as cube_face_dir() in _detail.cube.gdshaderinc and face_dir() in
// bake_cubemap.py; one flipped sign shows up as a mirrored or rotated face. Left
// unnormalized -- both users below are scale invariant except where noted.
vec3 face_direction(int face, vec2 uv) {
	vec2 st = uv * 2.0 - 1.0;
	if (face == 0) return vec3( 1.0, -st.y, -st.x);
	if (face == 1) return vec3(-1.0, -st.y,  st.x);
	if (face == 2) return vec3( st.x,  1.0,  st.y);
	if (face == 3) return vec3( st.x, -1.0, -st.y);
	if (face == 4) return vec3( st.x, -st.y,  1.0);
	return             vec3(-st.x, -st.y, -1.0);
}


// Inverse of SphereMesh's UV unwrap. atan(length(d.xz), d.y) is acos(normalize(d).y)
// without the normalize, and is well conditioned at the poles where acos in 32-bit is not
// (a 1e-7 error in d.y there becomes ~1e-3 rad, most of a source row).
vec2 direction_to_lonlat(vec3 direction) {
	float lon01 = (direction.x == 0.0 && direction.z == 0.0)
			? 0.0 // the exact pole, where atan is undefined and numpy's arctan2 gives 0
			: fract(atan(direction.x, direction.z) / TAU);
	return vec2(lon01, clamp(atan(length(direction.xz), direction.y) / PI, 0.0, 1.0));
}


// bilinear_equirect() from build_body_model.py, texel for texel. Its two axes use
// DIFFERENT conventions -- longitude is texel centers and wraps, latitude is endpoints
// (scaled by h - 1, so lat01 0 and 1 land on the first and last row centers) -- which no
// single sampler addressing mode reproduces.
vec4 sample_equirect(vec2 lonlat) {
	int width = int(source_size.x);
	int height = int(source_size.y);
	float fx = lonlat.x * source_size.x - 0.5;
	float fy = clamp(lonlat.y * (source_size.y - 1.0), 0.0, source_size.y - 1.0);
	float floor_x = floor(fx);
	float floor_y = floor(fy);
	float tx = fx - floor_x;
	float ty = fy - floor_y;
	// fx >= -0.5 always, so floor_x >= -1; GLSL's % truncates where Python's floors, so
	// the + width is load-bearing (a bare -1 % width stays -1 and reads out of bounds).
	int x0 = (int(floor_x) + width) % width;
	int x1 = (int(floor_x) + 1 + width) % width;
	int y0 = clamp(int(floor_y), 0, height - 1);
	int y1 = clamp(int(floor_y) + 1, 0, height - 1);
	// Work in 0-255 like the Python, which reads the image as float64 counts and never
	// normalizes. round() recovers the exact integer the hardware's byte/255 approximates,
	// so a run of equal texels averages to an exact integer instead of a hair under one --
	// which floor() below would otherwise turn into a systematic -1 (it made 94% of the
	// near-binary Earth.roughness mask one count too dark).
	vec4 texel_00 = round(texelFetch(source, ivec2(x0, y0), 0) * 255.0);
	vec4 texel_10 = round(texelFetch(source, ivec2(x1, y0), 0) * 255.0);
	vec4 texel_01 = round(texelFetch(source, ivec2(x0, y1), 0) * 255.0);
	vec4 texel_11 = round(texelFetch(source, ivec2(x1, y1), 0) * 255.0);
	// a + (b - a) * t rather than a * (1 - t) + b * t: the two agree in the float64 the
	// Python evaluates them in, but only this form is exactly a when a == b in 32-bit.
	vec4 top = texel_00 + (texel_10 - texel_00) * tx;
	vec4 bottom = texel_01 + (texel_11 - texel_01) * tx;
	return top + (bottom - top) * ty;
}


// Tangent space (R = east, G = north, B = up) -> object space at `direction`, matching
// bake_normal_face(). A tangent-space map cannot live on a cubemap at all -- each face has
// its own tangent basis, so cross-face filtering would mix frames -- so the rotation is
// baked in here against a clean analytic frame that, unlike the mesh TBN, is not
// degenerate at the poles.
// The frame is built from lonlat rather than from the direction's components, because
// that is what bake_normal_face() evaluates. The two agree everywhere except exactly at a
// pole, where the component form is 0/0 but lon01 is defined (0) and yields a valid frame.
vec3 to_object_space(vec2 lonlat, vec3 unit_direction, vec3 tangent_normal) {
	float longitude = TAU * lonlat.x;
	float colatitude = PI * lonlat.y;
	float cos_longitude = cos(longitude);
	float sin_longitude = sin(longitude);
	float cos_colatitude = cos(colatitude);
	float sin_colatitude = sin(colatitude);
	vec3 east = vec3(cos_longitude, 0.0, -sin_longitude);
	vec3 north = vec3(-cos_colatitude * sin_longitude, sin_colatitude,
			-cos_colatitude * cos_longitude);
	return tangent_normal.x * east + tangent_normal.y * north
			+ tangent_normal.z * unit_direction;
}


void fragment() {
	vec2 grid = UV * vec2(3.0, 2.0);
	vec2 cell = min(floor(grid), vec2(2.0, 1.0)); // min() guards the u == 1 edge
	int face = int(cell.y * 3.0 + cell.x);        // row-major, matching arrange_strip()
	vec2 face_uv = grid - cell;

	// Python supersamples the whole face at size * supersample and box-averages each
	// block, so the taps sit at the sub-texel centers of this one output texel.
	float texel = 1.0 / face_size;
	float tap_step = texel / float(supersample);
	vec2 first_tap = face_uv - vec2(0.5 * texel) + vec2(0.5 * tap_step);

	// Alpha rides along through the color path: a shell overlay (Earth.clouds.albedo) is
	// flat white with all of its coverage in alpha, so dropping it renders a solid shell.
	// An RGB source samples alpha as 1.0, giving an opaque strip the caller writes as RGB.
	vec4 accumulated = vec4(0.0);
	for (int row = 0; row < supersample; row++) {
		for (int column = 0; column < supersample; column++) {
			vec2 tap_uv = first_tap + vec2(float(column), float(row)) * tap_step;
			vec3 direction = face_direction(face, tap_uv);
			vec2 lonlat = direction_to_lonlat(direction);
			vec4 sampled = sample_equirect(lonlat);
			if (object_space_normal) {
				// Accumulate the VECTORS. Averaging encoded bytes and renormalizing
				// afterwards is a different operation, and it flattens relief.
				accumulated.rgb += to_object_space(lonlat, normalize(direction),
						sampled.rgb / 255.0 * 2.0 - 1.0);
			} else {
				accumulated += sampled;
			}
		}
	}
	accumulated /= float(supersample * supersample);

	if (object_space_normal) {
		// Renormalize the averaged vectors, then store the DEVIATION from this texel's own
		// direction rather than the normal: the direction sweeps the full range across a
		// face, and a block codec fitting that per 4x4 block prints a grid wherever a
		// specular lobe magnifies it. See bake_normal_face() in bake_cubemap.py.
		// An object-space normal has no alpha to carry; the strip writes as RGB.
		accumulated.rgb /= max(length(accumulated.rgb), 1e-12);
		vec3 residual = accumulated.rgb - normalize(face_direction(face, face_uv));
		accumulated = vec4((clamp(residual / normal_residual_scale, -1.0, 1.0) * 0.5 + 0.5)
				* 255.0, 255.0);
	}

	// Clip then TRUNCATE, in that order, because that is what numpy's .astype(np.uint8)
	// does. Matching the reference implementation exactly is worth more here than the half
	// count the truncation gives away: it makes the parity test binary, and makes
	// reconverting a shipped map a byte-level no-op rather than asset churn. If
	// bake_cubemap.py ever rounds instead, this must change with it.
	COLOR = floor(clamp(accumulated, 0.0, 255.0)) / 255.0;
}
