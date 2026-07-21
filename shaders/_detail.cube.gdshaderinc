// _detail.cube.gdshaderinc
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

// Cubemap counterpart of texture_bicubic() in _detail.gdshaderinc, for the
// direction-sampled (cubemap) surface shaders. A cubemap has no pole singularity
// or seam, but a fixed-resolution face still shows texel squares when magnified at
// close (orbital) range; this resamples C2-continuous bicubic so the magnified
// face reads smooth. Include _detail.gdshaderinc BEFORE this file -- cubic_weights()
// lives there and is shared.

// Godot / GL cube convention. cube_face_uv() is Godot's hardware forward map
// (direction -> face + face-uv); cube_face_dir() is its inverse. The two are a
// matched pair and must also match bake_cubemap.py's face_dir(), so a tap that
// leaves one face reconstructs the direction the neighbor face's texel sits on --
// which the hardware then resolves, giving cross-face bicubic for free (when the
// backend filters cube faces seamlessly; the whole point of the web test).
void cube_face_uv(vec3 dir, out int face, out vec2 uv) {
	vec3 a = abs(dir);
	float major;
	if (a.x >= a.y && a.x >= a.z) {
		major = a.x;
		if (dir.x >= 0.0) { face = 0; uv = vec2(-dir.z, -dir.y); }
		else              { face = 1; uv = vec2( dir.z, -dir.y); }
	} else if (a.y >= a.z) {
		major = a.y;
		if (dir.y >= 0.0) { face = 2; uv = vec2( dir.x,  dir.z); }
		else              { face = 3; uv = vec2( dir.x, -dir.z); }
	} else {
		major = a.z;
		if (dir.z >= 0.0) { face = 4; uv = vec2( dir.x, -dir.y); }
		else              { face = 5; uv = vec2(-dir.x, -dir.y); }
	}
	uv = uv / major * 0.5 + 0.5;
}


vec3 cube_face_dir(int face, vec2 uv) {
	vec2 st = uv * 2.0 - 1.0; // sc, tc in [-1, 1]; valid past the edge for cross-face taps
	if (face == 0) return vec3( 1.0, -st.y, -st.x); // +X
	if (face == 1) return vec3(-1.0, -st.y,  st.x); // -X
	if (face == 2) return vec3( st.x,  1.0,  st.y); // +Y
	if (face == 3) return vec3( st.x, -1.0, -st.y); // -Y
	if (face == 4) return vec3( st.x, -st.y,  1.0); // +Z
	return             vec3(-st.x, -st.y, -1.0);    // -Z
}


vec4 texture_bicubic_cube(samplerCube tex, vec3 dir) {
	int face;
	vec2 uv;
	cube_face_uv(dir, face, uv);

	float texsize = float(textureSize(tex, 0).x); // faces are square
	vec2 inv_texsize = vec2(1.0 / texsize);

	vec2 coord = uv * texsize - 0.5;
	vec2 fxy = fract(coord);
	coord -= fxy;

	vec4 wx = cubic_weights(fxy.x);
	vec4 wy = cubic_weights(fxy.y);

	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
	vec4 offset = c + vec4(wx.yw, wy.yw) / s;
	offset *= inv_texsize.xxyy; // offset.xy = the two u taps, offset.zw = the two v taps

	// Reconstruct each tap's direction on this face (uv may fall past [0,1] near an
	// edge; cube_face_dir stays valid and the hardware picks up the neighbor face).
	vec4 sample0 = texture(tex, cube_face_dir(face, vec2(offset.x, offset.z)));
	vec4 sample1 = texture(tex, cube_face_dir(face, vec2(offset.y, offset.z)));
	vec4 sample2 = texture(tex, cube_face_dir(face, vec2(offset.x, offset.w)));
	vec4 sample3 = texture(tex, cube_face_dir(face, vec2(offset.y, offset.w)));

	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);

	return mix(mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}
