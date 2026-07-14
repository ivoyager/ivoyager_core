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

// Depixelated background sky for IVWorldEnvironment that samples an equatorial
// (celestial-coordinate) Milky Way panorama, e.g. NASA's "Deep Star Maps 2020",
// AS-IS -- no reprojection bake. EYEDIR (the ecliptic world view direction) is
// rotated into the equatorial frame by the obliquity, then mapped to the image's
// RA/Dec layout. This lands the diffuse band in the sim's ecliptic frame, aligned
// with the IVStarsVisual points.
//
// The NASA map is drawn for the inside of the celestial sphere: RA = 0 at the
// horizontal center, RA increasing to the left (east), +Dec up (verified against
// the galactic-center bulge and the band's +62.9-deg peak). So u = fract(0.5 -
// RA/TAU); sampling raw RA/TAU instead comes out mirrored (a reflection about the
// RA 90/270 meridian). This is also why Environment.sky_rotation cannot orient the
// raw map: a rotation (det +1) cannot undo the reflection; the sampling must.
//
// texture_bicubic (shared with spheroid_surface.gdshader) resamples smoothly so the
// low-resolution image is not blocky when magnified. energy_multiplier mirrors
// PanoramaSkyMaterial's exposure; obliquity is set from IVAstronomy.

#include "_detail.gdshaderinc"

uniform sampler2D panorama : filter_linear, source_color, hint_default_black;
uniform float energy_multiplier : hint_range(0, 128) = 1.0;
uniform float obliquity = 0.40909281; // ecliptic->equatorial tilt (rad); set from IVAstronomy


void sky() {
	// Ecliptic -> equatorial about the vernal-equinox (x) axis; matches
	// IVAstronomy.ECLIPTIC_TO_EQUATORIAL_ROTATION.
	float cos_obl = cos(obliquity);
	float sin_obl = sin(obliquity);
	vec3 eye = EYEDIR;
	vec3 equatorial = vec3(eye.x, cos_obl * eye.y - sin_obl * eye.z,
			sin_obl * eye.y + cos_obl * eye.z);
	float right_ascension = atan(equatorial.y, equatorial.x); // [-PI, PI]
	float declination = asin(clamp(equatorial.z, -1.0, 1.0));
	// NASA map is inside-the-sphere: RA = 0 centered, RA increasing left. Negate and
	// half-offset RA so east-west is not mirrored; +Dec at top.
	vec2 uv = vec2(fract(0.5 - right_ascension / TAU), 0.5 - declination / PI);
	COLOR = texture_bicubic(panorama, uv).rgb * energy_multiplier;
}
