// starmap_background.gdshader
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
shader_type sky;

// Depixelated background sky for IVWorldEnvironment that samples an all-sky
// Milky Way panorama, e.g., NASA's "Deep Star Maps 2020".
//
// Environment.sky_rotation carries the whole frame change -- ecliptic to
// whatever frame the image is drawn in -- and EYEDIR arrives here already in
// the image's frame. This shader only projects: +z is the image's north pole,
// +x its center meridian. See IVWorldEnvironment.sky_rotation.
//
// texture_bicubic (shared with surface.gdshader) resamples smoothly
// so the low-resolution image is not blocky when magnified. energy_multiplier
// mirrors PanoramaSkyMaterial's exposure.

#include "_detail.gdshaderinc"
#include "_display.gdshaderinc"

uniform sampler2D panorama : filter_linear, source_color, hint_default_black;
uniform float energy_multiplier : hint_range(0, 128) = 1.0;
// Compensating-camera exposure; 1.0 when that system is off (see stars.gdshader). The
// panorama is an extended source, so exposure is its ONLY view-dependent term -- surface
// brightness holds across fov and resolution, which the star sprites compensate for and
// per-pixel sampling gets for free.
global uniform float iv_exposure;


void sky() {
	float longitude = atan(EYEDIR.y, EYEDIR.x); // [-PI, PI]
	float latitude = asin(clamp(EYEDIR.z, -1.0, 1.0));
	vec2 uv = vec2(fract(0.5 - longitude / TAU), 0.5 - latitude / PI);
	// Decoded on the way in and encoded on the way out (see _display.gdshaderinc), the same
	// convention as the spatial shaders: the sky pass expects display-referred COLOR on the
	// renderer that expects display-referred ALBEDO, and its own conversions then cancel.
	COLOR = display_write(display_decode(texture_bicubic(panorama, uv).rgb)
			* (energy_multiplier * iv_exposure));
}
