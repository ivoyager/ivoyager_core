# world_environment.gd
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
class_name IVWorldEnvironment
extends WorldEnvironment

## I, Voyager's WorldEnvironment for scene tree construction.
##
## This node uses default Environment and CameraAttributes resources from
## res://addons/ivoyager_core/resources.[br][br]
##
## Renderer-conditional Environment setup happens here at [method Node._ready]: the
## Compatibility brightness offset ([member gl_compatibility_exposure]) there, and the
## adjustment stage that [IVScreenshotManager] dims with everywhere else.[br][br]
##
## If [member add_starmap] is true (default), this node adds a low-resolution
## background panorama (the diffuse Milky Way / nebula sky) from the assets
## directory to the Environment's sky at startup, discovered by file prefix (see
## [member starmap_background_file_prefix]) and oriented by [member sky_rotation].
## The default Environment omits it because the Core plugin is stand-alone without
## assets; a missing file simply leaves the black clear-color background. Discrete
## stars are drawn separately by [IVStarsVisual].[br][br]

## If true, a background panorama discovered under [member starmaps_search] by
## [member starmap_background_file_prefix] is added to the Environment's sky as a
## [PanoramaSkyMaterial] at startup. A missing file leaves the clear-color background.
@export var add_starmap := true
## File prefix (see [IVFiles]) of the background sky panorama in [member
## starmaps_search]; e.g. [code]milkyway_galaxies_nebulea[/code] matches
## [code]milkyway_galaxies_nebulea.4096.exr[/code], so the asset resolution can
## change without a code edit. A panorama must be equirectangular and drawn to the
## astronomical convention (longitude 0 centered and increasing leftward, +latitude
## up); set [member sky_rotation] for the frame it is drawn in.
@export var starmap_background_file_prefix := "milkyway_background"
## Directories searched for the background panorama. Prepend a directory to
## prioritize a custom override.
var starmaps_search: Array[String] = ["res://addons/ivoyager_assets/starmaps"]
## Energy multiplier applied to the background sky ([code]starmap_background[/code]
## shader).
@export_range(0.0, 2.0, 0.01, "or_greater") var starmap_background_energy := 0.5
## Euler angles assigned to [member Environment.sky_rotation], which rotates the background
## panorama out of the frame it is drawn in and into the simulator's ecliptic frame. Zero
## means the panorama is already ecliptic. The default suits the galactic-coordinate
## panorama named by [member starmap_background_file_prefix]: it decomposes the ecliptic
## basis whose x-axis points at the galactic center (ICRS RA 266.40510, dec -28.936175) and
## z-axis at the north galactic pole (ICRS RA 192.85948, dec +27.12825), the IAU galactic
## frame as referred to ICRS by Hipparcos (ESA SP-1200, sect. 1.5.3).
@export var sky_rotation := Vector3(0.000351590, -1.050488534, -1.682016221)
## Multiplies all scene radiance (emission + lit surfaces + sky) before tonemapping;
## applied only under the Compatibility renderer to offset its dimmer output. Tune by eye.
@export var gl_compatibility_exposure := 1.2


func _ready() -> void:
	if IVGlobal.is_gl_compatibility:
		environment.tonemap_exposure = gl_compatibility_exposure
	else:
		# The adjustment stage, which [IVScreenshotManager] tweens for its capture dim. Kept
		# out of the Environment resource and off under Compatibility, where it is anything
		# but free: adjustments_enabled joins the gate that moves tonemapping out of the
		# scene shaders into a post pass, costing a full-resolution intermediate buffer, a
		# pass per frame, and a repermute of every scene shader -- a bill the web build would
		# pay always for an effect it wants for a moment. Forward+ folds it into a tonemap
		# pass that runs regardless, for a few ALU. Nothing here switches it back off, so a
		# project that wants it anyway can author it into its own Environment.
		environment.adjustment_enabled = true
	IVStateManager.assets_preloaded.connect(_on_asset_preloader_finished)


func _on_asset_preloader_finished() -> void:
	if add_starmap:
		_add_starmap_sky()


func _add_starmap_sky() -> void:
	var background: Texture2D = IVFiles.find_and_load_resource(starmaps_search,
		starmap_background_file_prefix)
	if !background:
		return

	# Depixelating sky shader (bicubic resample) that samples the background image as-is;
	# sky_rotation supplies the frame. See starmap_background.gdshader.
	var sky_material := ShaderMaterial.new()
	sky_material.shader = IVGlobal.resources[&"starmap_background_shader"]
	sky_material.set_shader_parameter(&"panorama", background)
	sky_material.set_shader_parameter(&"energy_multiplier", starmap_background_energy)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.sky_rotation = sky_rotation
	environment.background_mode = Environment.BG_SKY
