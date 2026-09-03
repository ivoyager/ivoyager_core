# psf_settings.gd
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
class_name IVPSFSettings
extends RefCounted

## The camera that images every source: PSF shape, flux response and color rendering.
##
## Shared by the catalog star field ([IVStarsVisual]) and each in-scene body's PSF quad
## ([IVBodyPSF]). Past its disc handoff an in-scene source [i]is[/i] a field star, so both
## must image through one camera. These values are that camera, and every one of them is a
## property of the observer rather than of anything observed -- which is what the name
## says: a point spread function belongs to an instrument by definition, never to a
## subject. They live here rather than on either visual because a value owned by one
## silently desyncs the other: the field would follow an edit and the quads would not,
## leaving them disagreeing with the sky around them.[br][br]
##
## These are the parameters of [code]_point_spread_function.gdshaderinc[/code]: most are
## arguments to a function in it, while [member intensity_scale] and [member intensity_gamma]
## are applied by each consumer where it forms its own intensity. Consumers apply via
## [method apply_to], on [signal changed] and once on build. See [code]stars.gdshader[/code]
## for what each value does, how it was calibrated against the NASA starmap_2020 reference,
## and why nothing clamps.[br][br]
##
## A [RefCounted] has no inspector, so the tuning surface lives on a node: [IVStarsVisual]'s
## "Point Spread Function" export group, whose setters write through to here. That holds while
## the sim runs -- an edit reaches every consumer through [signal changed]. The split is the
## point of the arrangement: an export needs a node to live on, the values need one home to be
## shared from, and keeping those apart is what lets a single edit move the star field and
## every body's quad together instead of desyncing them. So these are not the star field's
## settings, whatever the sliders sit next to.[br][br]
##
## Nothing here is a glow control: the [member glare_scale] wing is drawn in the shader, not
## by the engine's glow (bloom) pass.


## Emitted when any value changes. Consumers re-apply via [method apply_to].
signal changed()


## Width in px of the camera point-spread function that images every source, at any
## resolution. The sole input to a source's size, together with intensity. Also written
## to the [code]iv_psf_sigma[/code] shader global, through which a body's surface shaders
## image its sunlit rim with the same PSF (see [code]_photometry.gdshaderinc[/code]).
var psf_sigma := 0.5:
	set(value):
		if psf_sigma == value:
			return
		psf_sigma = value
		RenderingServer.global_shader_parameter_set(&"iv_psf_sigma", value)
		changed.emit()
## V magnitude mapping to flux 1.0, i.e. to [member intensity_scale].
var intensity_faint_mag := 6.5:
	set(value):
		if intensity_faint_mag == value:
			return
		intensity_faint_mag = value
		changed.emit()
## Flux compression exponent. 1.0 is photometric (no compression), as calibrated;
## below 1.0 compresses the rendered range a second time on top of the PSF saturation
## that already models a camera's own.
var intensity_gamma := 1.0:
	set(value):
		if intensity_gamma == value:
			return
		intensity_gamma = value
		changed.emit()
## Linear intensity of a source at [member intensity_faint_mag].
var intensity_scale := 0.5:
	set(value):
		if intensity_scale == value:
			return
		intensity_scale = value
		changed.emit()
## The fov (degrees) at which [member fov_compensation] neither brightens nor dims
## a source.
var fov_reference_deg := 50.0:
	set(value):
		if fov_reference_deg == value:
			return
		fov_reference_deg = value
		changed.emit()
## How much of the 1/tan^2(fov/2) point-source law to apply. 0 = off (sources hold
## brightness across zoom); 1 = full.
var fov_compensation := 1.0:
	set(value):
		if fov_compensation == value:
			return
		fov_compensation = value
		changed.emit()
## Saturation of a source's B-V color. 1.0 is the physical blackbody color, computed
## rather than tuned (see [code]color_from_b_v()[/code] in
## [code]_point_spread_function.gdshaderinc[/code]); 0 renders every source white; above 1.0
## exaggerates. Unlike the rest of this class it does not touch brightness or size:
## the ramp is normalized to peak channel 1.0 at any saturation.
var color_saturation := 1.0:
	set(value):
		if color_saturation == value:
			return
		color_saturation = value
		changed.emit()


## Amplitude at 1 px of a source's [code]r^-2[/code] glare wing, for a source of linear
## intensity 1.0. Zero turns the glare off entirely. The wing is the wide skirt a
## Gaussian core does not have; see [code]_point_spread_function.gdshaderinc[/code] for what it is,
## why it is drawn in the shader rather than left to the engine's glow pass, and why its
## amplitude carries a compression rather than the physical ~10 % of the source's light.
## The default is anchored: at the far sun it reproduces the Forward+ glow halo it
## replaces (31 px at 32 codes against a measured 29).
var glare_scale := 0.0126:
	set(value):
		if glare_scale == value:
			return
		glare_scale = value
		changed.emit()
## Flux compression for the glare's amplitude. The wing's outer radius grows as
## [code]intensity^(glare_gamma / 2)[/code], so the default is one doubling per 5.3
## magnitudes — against the Gaussian core's one per 19, which is why the far sun read as
## an ordinary star. 0.0 gives every source the same glare; 2.0 would be the physical
## law, which no frame can hold (see the include).
var glare_gamma := 0.286:
	set(value):
		if glare_gamma == value:
			return
		glare_gamma = value
		changed.emit()
## Largest glare radius in px at [member IVGlobal.reference_viewport_height], scaled with
## the render's own height. It bounds the AMPLITUDE, not the radius, so the wing still
## ends where it falls below one 8-bit step and the bound simply stops the glare growing;
## capping the radius instead would cut the wing mid-white and leave a ring. Only the last
## au or two before a source's disc resolves reaches it.
var glare_max_px := 384.0:
	set(value):
		if glare_max_px == value:
			return
		glare_max_px = value
		changed.emit()


## Pushes only the [code]color_from_b_v()[/code] inputs to [param shader_material]. For a
## consumer that maps B-V through the shared ramp but takes none of the point-source
## photometry — a resolved star's disc ([code]sun_surface.gdshader[/code]), which is
## lit by geometry rather than by a PSF. It still needs this: the disc and the quad
## trade places at the handoff, and a B-V that changed color across that trade would
## show. [method apply_to] calls this, so a point-source consumer needs only that.
func apply_color_to(shader_material: ShaderMaterial) -> void:
	shader_material.set_shader_parameter(&"color_saturation", color_saturation)


## Pushes every value to [param shader_material], which must declare the PSF
## uniforms (see [code]stars.gdshader[/code] or
## [code]body_psf.gdshader[/code]). Keeping the uniform names here rather than in
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
	shader_material.set_shader_parameter(&"glare_scale", glare_scale)
	shader_material.set_shader_parameter(&"glare_gamma", glare_gamma)
	shader_material.set_shader_parameter(&"glare_max_px", glare_max_px)
