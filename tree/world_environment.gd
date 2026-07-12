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
## If [member add_starmap] is true (default), this node adds a low-resolution
## background panorama (the diffuse Milky Way / nebula sky) from the assets
## directory to the Environment's sky at startup, discovered by file prefix (see
## [member starmap_background_file_prefix]). The default Environment omits it
## because the Core plugin is stand-alone without assets; a missing file simply
## leaves the black clear-color background. Discrete stars are drawn separately
## by [IVStarsVisual].[br][br]

## If true, a background panorama discovered under [member starmaps_search] by
## [member starmap_background_file_prefix] is added to the Environment's sky as a
## [PanoramaSkyMaterial] at startup. A missing file leaves the clear-color background.
@export var add_starmap := true
## File prefix (see [IVFiles]) of the background sky panorama in [member
## starmaps_search]; e.g. [code]starmap_background[/code] matches
## [code]starmap_background.1024.jpg[/code], so the asset resolution can change
## without a code edit.
@export var starmap_background_file_prefix := &"starmap_background"
## Directories searched for the background panorama. Prepend a directory to
## prioritize a custom override.
var starmaps_search: Array[String] = ["res://addons/ivoyager_assets/starmaps"]
## Energy multiplier applied to the background sky ([code]starmap_background[/code]
## shader). The NASA Milky Way image is near-white in the galactic bulge at full
## energy; lower this to dim the diffuse band and lift star contrast [b]without
## rebaking the image[/b]. (For a scene-wide alternative, set
## [code]bg_energy_multiplier[/code] on the shared Environment resource instead.)
@export_range(0.0, 2.0, 0.01, "or_greater") var starmap_background_energy := 0.05
## Multiplies all scene radiance (emission + lit surfaces + sky) before tonemapping;
## applied only under the Compatibility renderer to offset its dimmer output.
@export var gl_compatibility_exposure := 1.2  # tune by eye


func _ready() -> void:
	if IVGlobal.is_gl_compatibility:
		environment.tonemap_exposure = gl_compatibility_exposure
	IVStateManager.assets_preloaded.connect(_on_asset_preloader_finished)


func _on_asset_preloader_finished() -> void:
	if add_starmap:
		_add_starmap_sky()


func _add_starmap_sky() -> void:
	var background: Texture2D = IVFiles.find_and_load_resource(starmaps_search,
			String(starmap_background_file_prefix))
	if !background:
		return

	# Depixelating sky shader (bicubic resample) that samples the equatorial background
	# image as-is and rotates it into the ecliptic frame; see starmap_background.gdshader
	# for why Environment.sky_rotation can't do this (handedness).
	var sky_material := ShaderMaterial.new()
	sky_material.shader = IVGlobal.resources[&"starmap_background_shader"]
	sky_material.set_shader_parameter(&"panorama", background)
	sky_material.set_shader_parameter(&"energy_multiplier", starmap_background_energy)
	sky_material.set_shader_parameter(&"obliquity", IVAstronomy.OBLIQUITY_OF_THE_ECLIPTIC)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
