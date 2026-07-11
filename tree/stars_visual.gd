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
## ivoyager_assets is absent).

## Path prefix for the star binaries. The loader appends
## [code].<magnitude>.ivbinary[/code] for each bin in [member BINARY_FILE_MAGNITUDES].
@export var stars_binary_path := "res://addons/ivoyager_assets/starmaps/hipparcos_stars"

## Loads magnitude bins up to and including this V-magnitude cutoff. Lower it (or
## remove bin files from the asset directory) to trade completeness for size.
@export var magnitude_cutoff := 99.9

# Tuning uniforms pushed to the stars shader material; editing one in the inspector
# updates the live material. See stars.gdshader for each uniform's role.
@export_group("Star Appearance")
@export_range(-2.0, 4.0, 0.1) var size_bright_mag := -1.5:
	set(value):
		size_bright_mag = value
		_set_uniform(&"size_bright_mag", value)
@export_range(0.0, 14.0, 0.1) var size_faint_mag := 6.5:
	set(value):
		size_faint_mag = value
		_set_uniform(&"size_faint_mag", value)
@export_range(0.5, 8.0, 0.1) var point_size_min := 1.3:
	set(value):
		point_size_min = value
		_set_uniform(&"point_size_min", value)
@export_range(1.0, 32.0, 0.5, "or_greater") var point_size_max := 8.0:
	set(value):
		point_size_max = value
		_set_uniform(&"point_size_max", value)
@export_range(1.0, 8.0, 0.1, "or_greater") var point_size_floor := 3.0:
	set(value):
		point_size_floor = value
		_set_uniform(&"point_size_floor", value)
@export_range(0.0, 14.0, 0.1) var intensity_faint_mag := 6.5:
	set(value):
		intensity_faint_mag = value
		_set_uniform(&"intensity_faint_mag", value)
@export_range(0.05, 1.0, 0.01) var intensity_gamma := 0.35:
	set(value):
		intensity_gamma = value
		_set_uniform(&"intensity_gamma", value)
@export_range(0.0, 3.0, 0.01, "or_greater") var intensity_scale := 0.5:
	set(value):
		intensity_scale = value
		_set_uniform(&"intensity_scale", value)
@export_range(1.0, 20.0, 0.1, "or_greater") var intensity_max := 6.0:
	set(value):
		intensity_max = value
		_set_uniform(&"intensity_max", value)
@export_range(1.0, 170.0, 0.1) var fov_reference_deg := 51.79:
	set(value):
		fov_reference_deg = value
		_set_uniform(&"reference_tan_half_fov", tan(deg_to_rad(value) / 2.0))
@export_range(0.0, 1.0, 0.05, "or_greater") var fov_compensation := 1.0:
	set(value):
		fov_compensation = value
		_set_uniform(&"fov_compensation", value)

## Magnitude-bin upper edges; must match the bins written by
## [code]tools/build_star_binaries.py[/code]. Each bin file holds stars up to its edge.
const BINARY_FILE_MAGNITUDES: Array[String] = ["2.0", "3.0", "4.0", "5.0", "6.0", "7.0", "8.0",
		"9.0", "99.9"]

const _ARRAY_FLAGS := Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
const _BINARY_MAGIC := 0x54535649 # b"IVST", little-endian
const _BINARY_VERSION := 1

var _shader_material: ShaderMaterial



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
	_apply_star_uniforms()
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


func _apply_star_uniforms() -> void:
	_set_uniform(&"size_bright_mag", size_bright_mag)
	_set_uniform(&"size_faint_mag", size_faint_mag)
	_set_uniform(&"point_size_min", point_size_min)
	_set_uniform(&"point_size_max", point_size_max)
	_set_uniform(&"point_size_floor", point_size_floor)
	_set_uniform(&"intensity_faint_mag", intensity_faint_mag)
	_set_uniform(&"intensity_gamma", intensity_gamma)
	_set_uniform(&"intensity_scale", intensity_scale)
	_set_uniform(&"intensity_max", intensity_max)
	_set_uniform(&"reference_tan_half_fov", tan(deg_to_rad(fov_reference_deg) / 2.0))
	_set_uniform(&"fov_compensation", fov_compensation)


# Live-updates one shader uniform. No-op until the material exists (the property
# setters fire during scene load, before _build creates the material).
func _set_uniform(uniform: StringName, value: float) -> void:
	if _shader_material:
		_shader_material.set_shader_parameter(uniform, value)


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
