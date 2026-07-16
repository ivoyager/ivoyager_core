# stars_visual.gd
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
class_name IVStarsVisual
extends MeshInstance3D

## Catalog star field drawn as farwarp-remapped point sprites.
##
## Builds one [constant Mesh.PRIMITIVE_POINTS] surface from magnitude-binned star
## binaries (produced by [code]tools/build_star_binaries.py[/code]) on [signal
## IVStateManager.core_initialized]. Each vertex is a star at its true ecliptic
## position (internal units); a [code]CUSTOM0[/code] channel carries raw
## (V magnitude, B-V), which the [code]stars[/code] shader converts to point
## size, brightness and color. The shader's per-vertex farwarp remap (shared with
## the small-body points) keeps distant stars inside the camera far plane and
## behind every simulation visual at any zoom.[br][br]
##
## Authored as a fixed node under [code]Universe[/code] (no PERSIST_MODE), so it
## rides the [IVCamera] origin shift automatically, builds once, and survives
## system rebuilds. No-ops with a warning if no binaries resolve (e.g. when
## ivoyager_assets is absent).[br][br]
##
## Note: Godot Editor shows a scene warning for missing mesh. The mesh is built
## procedurally, so you can ignore the warning.


## Magnitude-bin upper edges; must match the bins written by
## [code]tools/build_star_binaries.py[/code]. Each bin file holds stars up to its edge.
const BINARY_FILE_MAGNITUDES: Array[String] = ["2.0", "3.0", "4.0", "5.0", "6.0", "7.0", "8.0",
		"9.0", "99.9"]

const _ARRAY_FLAGS := Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
const _BINARY_MAGIC := 0x54535649 # b"IVST", little-endian
const _BINARY_VERSION := 1

## Path prefix for the star binaries. The loader appends
## [code].<magnitude>.ivbinary[/code] for each bin in [member BINARY_FILE_MAGNITUDES].
@export var stars_binary_path := "res://addons/ivoyager_assets/starmaps/hipparcos_stars"

## Loads magnitude bins up to and including this V-magnitude cutoff. Lower it (or
## remove bin files from the asset directory) to trade completeness for size.
@export var magnitude_cutoff := 99.9

# The tuning surface for IVStarSettings, which every star point sprite reads -- this
# field and each in-scene sun's far point alike, so an edit here moves both. Values
# write through on change (and on build, once the settings object exists); the live
# material updates from the settings object's 'changed' signal, not from these setters.
# See stars.gdshader for each uniform's role. Each range runs from one visibly wrong
# extreme to the other, so dragging a slider end to end shows what the uniform does;
# the shipped value sits well inside.
@export_group("Star Appearance")
## 0.1 = sub-pixel specks that scintillate; 1.5 = fat blurry discs.
@export_range(0.1, 1.5, 0.05, "or_greater") var psf_sigma := 0.5:
	set(value):
		psf_sigma = value
		if _star_settings:
			_star_settings.psf_sigma = value
## 0 = only the very brightest stars remain; 14 = every star saturates to white.
@export_range(0.0, 14.0, 0.1) var intensity_faint_mag := 6.5:
	set(value):
		intensity_faint_mag = value
		if _star_settings:
			_star_settings.intensity_faint_mag = value
## 0.05 = every star the same brightness; 2.0 = only a handful survive, the rest go black.
@export_range(0.05, 2.0, 0.05) var intensity_gamma := 1.0:
	set(value):
		intensity_gamma = value
		if _star_settings:
			_star_settings.intensity_gamma = value
## 0 = no stars at all; 1.5 = the field washes out to saturated blobs.
@export_range(0.0, 1.5, 0.01, "or_greater") var intensity_scale := 0.5:
	set(value):
		intensity_scale = value
		if _star_settings:
			_star_settings.intensity_scale = value
## The fov at which [member fov_compensation] neither brightens nor dims the field. Away
## from the camera's actual fov the whole field shifts: 10 = far too dim, 120 = blown out.
@export_range(10.0, 120.0, 0.5) var fov_reference_deg := 50.0:
	set(value):
		fov_reference_deg = value
		if _star_settings:
			_star_settings.fov_reference_deg = value
## 0 = stars hold brightness as you zoom (they swamp or fade against the background);
## 2 = double-compensated, so zooming in blows the field out.
@export_range(0.0, 2.0, 0.05) var fov_compensation := 1.0:
	set(value):
		fov_compensation = value
		if _star_settings:
			_star_settings.fov_compensation = value
## 0 = a white field; 1 = each star's physical blackbody color; 2.5 = a candy-colored sky.
## Unlike the sliders above, this changes no star's brightness or size.
@export_range(0.0, 2.5, 0.05) var color_saturation := 1.0:
	set(value):
		color_saturation = value
		if _star_settings:
			_star_settings.color_saturation = value

var _shader_material: ShaderMaterial
var _star_settings: IVStarSettings



func _ready() -> void:
	# A fixed scene node's _ready() precedes core init, so the stars shader isn't
	# registered yet; build on core_initialized (resources populated and frozen).
	if IVStateManager.initialized_core:
		_build()
	else:
		IVStateManager.core_initialized.connect(_build, CONNECT_ONE_SHOT)


func _build() -> void:
	var vertices := PackedVector3Array()
	var magnitudes_colors := PackedFloat32Array() # (V_mag, B-V) per vertex -> CUSTOM0
	var max_distance_sq := 0.0
	for magnitude_str in BINARY_FILE_MAGNITUDES:
		if magnitude_str.to_float() > magnitude_cutoff:
			break
		max_distance_sq = _append_binary(magnitude_str, vertices, magnitudes_colors, max_distance_sq)
	if vertices.is_empty():
		push_warning("IVStarsVisual: no star binaries found at '%s.*.ivbinary'" % stars_binary_path)
		return

	_shader_material = ShaderMaterial.new()
	_shader_material.shader = IVGlobal.resources[&"stars_shader"]
	material_override = _shader_material
	_star_settings = IVGlobal.program[&"StarSettings"]
	_push_star_settings()
	_star_settings.changed.connect(_apply_star_uniforms)
	_apply_star_uniforms() # _push_star_settings emits nothing if every export is a default
	cast_shadow = SHADOW_CASTING_SETTING_OFF

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_CUSTOM0] = magnitudes_colors
	var points_mesh := ArrayMesh.new()
	points_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays, [], {}, _ARRAY_FLAGS)
	# Frustum culling tests this AABB against the far plane, but farwarp-remapped
	# points stay on-screen even when the true-scale test fails; size the AABB so
	# it always contains the camera (as IVSBGPositionsVisual does for its points).
	var half_extent := maxf(sqrt(max_distance_sq), IVCoreSettings.max_camera_distance)
	var half_aabb := half_extent * Vector3.ONE
	points_mesh.custom_aabb = AABB(-half_aabb, 2.0 * half_aabb)
	mesh = points_mesh


# Seeds the shared settings from this node's authored exports. The property setters
# cannot: they fire during scene load, before IVCoreInitializer has built the settings
# object, so their write-through no-ops and the authored values would never arrive.
func _push_star_settings() -> void:
	_star_settings.psf_sigma = psf_sigma
	_star_settings.intensity_faint_mag = intensity_faint_mag
	_star_settings.intensity_gamma = intensity_gamma
	_star_settings.intensity_scale = intensity_scale
	_star_settings.fov_reference_deg = fov_reference_deg
	_star_settings.fov_compensation = fov_compensation
	_star_settings.color_saturation = color_saturation


func _apply_star_uniforms() -> void:
	_star_settings.apply_to(_shader_material)


# Appends one magnitude bin's stars to [param vertices] (internal units) and
# [param magnitudes_colors] (CUSTOM0 float pairs), returning the running maximum
# squared distance for the AABB. A missing file is skipped silently (missing
# bin = no items, as with the asteroid binaries).
func _append_binary(magnitude_str: String, vertices: PackedVector3Array,
		magnitudes_colors: PackedFloat32Array, max_distance_sq: float) -> float:
	var path := stars_binary_path + "." + magnitude_str + ".ivbinary"
	var file := FileAccess.open(path, FileAccess.READ)
	if !file:
		return max_distance_sq
	if file.get_32() != _BINARY_MAGIC:
		push_warning("IVStarsVisual: bad magic in '%s'" % path)
		return max_distance_sq
	var version := file.get_32()
	if version != _BINARY_VERSION:
		push_warning("IVStarsVisual: unexpected version %s in '%s'" % [version, path])
	var count := file.get_32()
	if count == 0:
		return max_distance_sq
	var position_floats := file.get_buffer(count * 12).to_float32_array() # x,y,z SI meters
	var custom_floats := file.get_buffer(count * 8).to_float32_array() # V_mag, B-V
	file.close()

	# SI meters -> internal units. Mandatory before the shader: raw meters (~1e19
	# for the 1 kpc shell) overflow float32 in farwarp()'s length() -> +inf/NaN.
	const METER := IVUnits.METER
	var base := vertices.size()
	vertices.resize(base + count)
	var i := 0
	while i < count:
		var k := i * 3
		var star_position := Vector3(position_floats[k], position_floats[k + 1],
				position_floats[k + 2]) * METER
		vertices[base + i] = star_position
		var distance_sq := star_position.length_squared()
		if distance_sq > max_distance_sq:
			max_distance_sq = distance_sq
		i += 1
	magnitudes_colors.append_array(custom_floats)
	return max_distance_sq
