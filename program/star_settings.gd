# star_settings.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
# I, Voyager is a registered trademark of Charlie Whitfield in the US
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************************
class_name IVStarSettings
extends RefCounted

## Photometry shared by every star point sprite: the catalog field
## ([IVStarsVisual]) and each in-scene star's far point ([IVSpheroidModel]
## sun-mode).
##
## Past its disc handoff a sun [i]is[/i] a field star, so both must image through
## one camera. These values are that camera. They live here rather than on either
## visual because a value owned by one silently desyncs the other: the field would
## follow an edit and the sun would not, leaving the sun disagreeing with the sky
## around it.[br][br]
##
## [IVStarsVisual]'s "Star Appearance" exports are the tuning surface and write
## through to here. Consumers apply via [method apply_to], on [signal changed] and
## once on build. See [code]stars.gdshader[/code] for what each value does, how it
## was calibrated against the NASA starmap_2020 reference, and why nothing clamps.[br][br]
##
## FUTURE_BLOOM_IMPLEMENTATION: nothing here is a glow control, and enabling glow
## would not merely need tuning — two things below the settings layer are wrong for
## it. First, the sun's disc and its far point crossfade in size but not in bloomable
## energy: the disc writes its surface brightness (~3.0, hardcoded in [IVSpheroidModel]
## sun-mode) while the point writes up to the cap in
## [code]star_point_light()[/code] (32768, a shader literal), so the handoff that
## matches on screen would step by orders of magnitude in halo. Those two values are
## unrelated today and would have to be co-calibrated. Second, that cap is not a
## brightness choice but a float16 limit (see [code]_star_point.gdshaderinc[/code]),
## and the sun sits at it everywhere the camera can reach — so its bloom could only
## grow through saturated area, not in proportion to true brightness as the star field
## does. The field itself is glow-ready: its brightest star peaks well under the cap,
## so it blooms proportionally and nothing overflows.[br][br]
##
## No member here can substitute. Each rescales point-source photometry [i]globally[/i],
## so any change large enough to move the sun moves the field with it — and none
## reaches the disc, which is where the discontinuity lives. Fixing this likely adds
## members here (the cap and the disc's brightness both become shared, since the field
## and the sun must stay welded), rather than repurposing existing ones.


## Emitted when any value changes. Consumers re-apply via [method apply_to].
signal changed()


## Width in px of the camera point-spread function that images every star, at any
## resolution. The sole input to star size, together with intensity.
var psf_sigma := 0.5:
	set(value):
		if psf_sigma == value:
			return
		psf_sigma = value
		changed.emit()
## V magnitude mapping to flux 1.0, i.e. to [member intensity_scale].
var intensity_faint_mag := 6.5:
	set(value):
		if intensity_faint_mag == value:
			return
		intensity_faint_mag = value
		changed.emit()
## Flux compression exponent. 1.0 is photometric (no compression), as calibrated;
## below 1.0 compresses the field a second time on top of the PSF saturation that
## already models a camera's own.
var intensity_gamma := 1.0:
	set(value):
		if intensity_gamma == value:
			return
		intensity_gamma = value
		changed.emit()
## Linear intensity of a star at [member intensity_faint_mag].
var intensity_scale := 0.5:
	set(value):
		if intensity_scale == value:
			return
		intensity_scale = value
		changed.emit()
## The fov (degrees) at which [member fov_compensation] neither brightens nor dims
## the field.
var fov_reference_deg := 50.0:
	set(value):
		if fov_reference_deg == value:
			return
		fov_reference_deg = value
		changed.emit()
## How much of the 1/tan^2(fov/2) point-source law to apply. 0 = off (stars hold
## brightness across zoom); 1 = full.
var fov_compensation := 1.0:
	set(value):
		if fov_compensation == value:
			return
		fov_compensation = value
		changed.emit()
## Saturation of a star's B-V color. 1.0 is the physical blackbody color, computed
## rather than tuned (see [code]star_color()[/code] in
## [code]_star_point.gdshaderinc[/code]); 0 renders every star white; above 1.0
## exaggerates. Unlike the rest of this class it does not touch brightness or size:
## the ramp is normalized to peak channel 1.0 at any saturation.
var color_saturation := 1.0:
	set(value):
		if color_saturation == value:
			return
		color_saturation = value
		changed.emit()


## Pushes only the [code]star_color()[/code] inputs to [param shader_material]. For a
## consumer that maps B-V through the shared ramp but takes none of the point-source
## photometry — a resolved star's disc ([code]sun_surface.gdshader[/code]), which is
## lit by geometry rather than by a PSF. It still needs this: the disc and the far point
## trade places at the handoff, and a B-V that changed color across that trade would
## show. [method apply_to] calls this, so a point-source consumer needs only that.
func apply_color_to(shader_material: ShaderMaterial) -> void:
	shader_material.set_shader_parameter(&"color_saturation", color_saturation)


## Pushes every value to [param shader_material], which must declare the star
## photometry uniforms (see [code]stars.gdshader[/code] or
## [code]sun_point.gdshader[/code]). Keeping the uniform names here rather than in
## each consumer is the point: two visuals naming them separately is how they drift.
func apply_to(shader_material: ShaderMaterial) -> void:
	apply_color_to(shader_material)
	shader_material.set_shader_parameter(&"psf_sigma", psf_sigma)
	shader_material.set_shader_parameter(&"intensity_faint_mag", intensity_faint_mag)
	shader_material.set_shader_parameter(&"intensity_gamma", intensity_gamma)
	shader_material.set_shader_parameter(&"intensity_scale", intensity_scale)
	shader_material.set_shader_parameter(&"reference_tan_half_fov",
			tan(deg_to_rad(fov_reference_deg) / 2.0))
	shader_material.set_shader_parameter(&"fov_compensation", fov_compensation)
