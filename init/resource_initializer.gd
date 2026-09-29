# resource_initializer.gd
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
class_name IVResourceInitializer
extends RefCounted

## Initializes shared resources that do not depend on ivoyager_assets.
##
## Resources are added to IVGlobal.resources. These resources are preloaded or
## constructed according to property dictionaries here and do not depend on the
## presence of ivoyager_assets (see [IVAssetPreloader] for that).


## The coarsest rung of the shared sphere's LOD ladder. One rung below the coarsest an
## [IVBodyPSF] handoff can expose (2.5 px), so it is set by the ladder's sagitta budget rather
## than by project taste — see [method get_sphere_lod_resolutions].
const SPHERE_LOD_FLOOR_RESOLUTION := 16


## Resources to preload and add to [member IVGlobal.resources]. Modify before
## construction (e.g., from a preinitializer script) to add or replace shaders
## and other resources.
var preloads: Dictionary[StringName, Resource] = {
	# shaders
	orbiting_positions_id_shader = preload(
			"res://addons/ivoyager_core/shaders/orbiting_positions_id.gdshader"),
	orbiting_positions_lp_id_shader = preload(
			"res://addons/ivoyager_core/shaders/orbiting_positions_lp_id.gdshader"),
	path_id_shader = preload("res://addons/ivoyager_core/shaders/path_id.gdshader"),
	instance_id_shader = preload("res://addons/ivoyager_core/shaders/instance_id.gdshader"),
	path_shader = preload("res://addons/ivoyager_core/shaders/path.gdshader"),
	farwarp_vertex_shader = preload("res://addons/ivoyager_core/shaders/farwarp_vertex.gdshader"),
	rings_shader = preload("res://addons/ivoyager_core/shaders/rings.gdshader"),
	cloud_shell_shader = preload("res://addons/ivoyager_core/shaders/cloud_shell.gdshader"),
	cloud_shell_cube_shader = preload(
			"res://addons/ivoyager_core/shaders/cloud_shell.cube.gdshader"),
	atmosphere_limb_shader = preload("res://addons/ivoyager_core/shaders/atmosphere_limb.gdshader"),
	surface_shader = preload("res://addons/ivoyager_core/shaders/surface.gdshader"),
	surface_cube_shader = preload("res://addons/ivoyager_core/shaders/surface.cube.gdshader"),
	# Textureless procedural surface; no cube variant, because it samples no texture.
	band_pattern_shader = preload("res://addons/ivoyager_core/shaders/band_pattern.gdshader"),
	# The above for a body with no atmosphere (IVAssetPreloader.airless_shader_variants).
	cloud_shell_airless_shader = preload(
			"res://addons/ivoyager_core/shaders/cloud_shell.airless.gdshader"),
	cloud_shell_cube_airless_shader = preload(
			"res://addons/ivoyager_core/shaders/cloud_shell.cube.airless.gdshader"),
	surface_airless_shader = preload("res://addons/ivoyager_core/shaders/surface.airless.gdshader"),
	surface_cube_airless_shader = preload(
			"res://addons/ivoyager_core/shaders/surface.cube.airless.gdshader"),
	band_pattern_airless_shader = preload(
			"res://addons/ivoyager_core/shaders/band_pattern.airless.gdshader"),
	# The above and the limb for a body with an atmosphere under Atmosphere Quality Min
	# (IVAssetPreloader.min_shader_variants).
	cloud_shell_min_shader = preload("res://addons/ivoyager_core/shaders/cloud_shell.min.gdshader"),
	cloud_shell_cube_min_shader = preload(
			"res://addons/ivoyager_core/shaders/cloud_shell.cube.min.gdshader"),
	atmosphere_limb_min_shader = preload(
			"res://addons/ivoyager_core/shaders/atmosphere_limb.min.gdshader"),
	surface_min_shader = preload("res://addons/ivoyager_core/shaders/surface.min.gdshader"),
	surface_cube_min_shader = preload(
			"res://addons/ivoyager_core/shaders/surface.cube.min.gdshader"),
	band_pattern_min_shader = preload(
			"res://addons/ivoyager_core/shaders/band_pattern.min.gdshader"),
	stars_shader = preload("res://addons/ivoyager_core/shaders/stars.gdshader"),
	# Textureless procedural photosphere; no cube variant, because it samples no texture.
	photosphere_shader = preload("res://addons/ivoyager_core/shaders/photosphere.gdshader"),
	body_psf_shader = preload(
			"res://addons/ivoyager_core/shaders/body_psf.gdshader"),
	starmap_background_shader = preload("res://addons/ivoyager_core/shaders/starmap_background.gdshader"),
}

## Callables that build shared resources (e.g., the common sphere mesh).
## Each Callable is invoked with no arguments and its return value is stored
## under the matching key in [member IVGlobal.resources].
var constructors: Dictionary[StringName, Callable]= {
	&"limb_annulus_mesh" : _make_limb_annulus_mesh.bind(IVCoreSettings.max_sphere_resolution,
			IVCoreSettings.limb_annulus_rows),
	&"plane_mesh" : _make_plane_mesh.bind(IVCoreSettings.plane_mesh_subdivisions),
	&"circle_mesh" : _make_circle_mesh.bind(IVCoreSettings.vertecies_per_conic_mesh),
	&"circle_mesh_low_res" : _make_circle_mesh.bind(IVCoreSettings.vertecies_per_orbit_low_res),
	&"parabola_mesh" : _make_open_conic_mesh.bind(IVCoreSettings.vertecies_per_conic_mesh,
			1.0, IVCoreSettings.open_conic_max_radius),
	&"rectangular_hyperbola_mesh" : _make_open_conic_mesh.bind(IVCoreSettings.vertecies_per_conic_mesh,
			sqrt(2.0), IVCoreSettings.open_conic_max_radius),
}

var _resources: Dictionary = IVGlobal.resources



func _init() -> void:
	_add_sphere_lod_constructors()
	_add_preloads()
	_make_shared_resources()
	# Not a rung of its own but the same object as the finest, for a caller that wants the shared
	# sphere without choosing one.
	_resources[&"sphere_mesh"] = _resources[get_sphere_mesh_key(
			IVCoreSettings.max_sphere_resolution)]
	IVStateManager.core_init_program_objects_instantiated.connect(_remove_self)



## Returns the [member IVGlobal.resources] key of the shared sphere built at [param resolution].
## [IVShellsModel] calls this to select a rung, so the two sides cannot name a mesh differently.
static func get_sphere_mesh_key(resolution: int) -> StringName:
	return StringName("sphere_mesh_%d" % resolution)


## Returns the shared sphere's LOD ladder, finest first: [member
## IVCoreSettings.max_sphere_resolution] halved down to [constant SPHERE_LOD_FLOOR_RESOLUTION].
## Each rung holds the same sub-pixel silhouette error over a 4x range of on-screen body size,
## which is what lets [IVShellsModel] pick one by that size alone.
static func get_sphere_lod_resolutions() -> Array[int]:
	var resolutions: Array[int] = []
	var resolution := IVCoreSettings.max_sphere_resolution
	while resolution >= SPHERE_LOD_FLOOR_RESOLUTION:
		resolutions.append(resolution)
		@warning_ignore("integer_division")
		resolution = resolution / 2
	return resolutions



func _remove_self() -> void:
	IVGlobal.program.erase(&"ResourceInitializer")


func _add_sphere_lod_constructors() -> void:
	for resolution in get_sphere_lod_resolutions():
		constructors[get_sphere_mesh_key(resolution)] = _make_sphere_mesh.bind(resolution)


func _add_preloads() -> void:
	for key in preloads:
		_resources[key] = preloads[key]


func _make_shared_resources() -> void:
	for key in constructors:
		var constructor := constructors[key]
		_resources[key] = constructor.call()


# constructor callables

# One rung of the shared sphere LOD ladder for stars, planets and moons, keyed by
# get_sphere_mesh_key(). A unit sphere (radius = 1.0; height = 2.0), scaled for individual
# [IVBody] oblateness by [IVBodyVisual]. Rings are half the radial segments: that is what makes
# the facets square, so one number sizes the mesh.
func _make_sphere_mesh(resolution := 64) -> SphereMesh:
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radial_segments = resolution
	@warning_ignore("integer_division")
	sphere_mesh.rings = resolution / 2
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 2.0
	return sphere_mesh


# Shared annulus for an atmosphere limb shell (see [member IVShellsModel.shader_meshes]). Its
# vertices hold (azimuth, row) parameters rather than positions -- atmosphere_limb.gdshader
# places them each frame -- encoded so its computed AABB is the finest sphere rung's to float
# rounding, since [IVBody2DCapturer] frames a staged body by that AABB.
func _make_limb_annulus_mesh(segments := 64, rows := 8) -> ArrayMesh:
	# The sphere's widest ring rather than 1: SphereMesh spaces sphere_rings + 1 bands pole to
	# pole, so an even ring count leaves no ring on the equator. The finest rung's rings, since
	# that is the sphere this mesh must match; a body drawing a coarser rung differs by under
	# 0.03 % of the radius, far inside the framing tolerance.
	@warning_ignore("integer_division")
	var sphere_rings := segments / 2
	var extent := sin(PI * floori((sphere_rings + 1) / 2.0) / (sphere_rings + 1))
	var columns := rows + 1
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for segment in segments:
		var azimuth := TAU * segment / segments
		for row in columns:
			vertices.append(Vector3(extent * sin(azimuth), 2.0 * row / rows - 1.0,
					extent * cos(azimuth)))
			uvs.append(Vector2(float(segment) / segments, float(row) / rows))
	# Clockwise on screen, Godot's front face: the shader turns azimuth counterclockwise as the
	# camera sees it, and rows run outward.
	var indices := PackedInt32Array()
	for segment in segments:
		var inner := segment * columns
		var next_inner := (segment + 1) % segments * columns
		for row in rows:
			indices.append_array(PackedInt32Array([inner + row, next_inner + row, inner + row + 1,
					next_inner + row, next_inner + row + 1, inner + row + 1]))
	# Unused by the shader, but a Forward+ pipeline is keyed by vertex format: carrying the
	# sphere's attributes lets the shader warm-up's quad compile this surface's pipeline.
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var tangents := PackedFloat32Array()
	tangents.resize(vertices.size() * 4)
	for vertex_index in vertices.size():
		tangents[vertex_index * 4] = 1.0
		tangents[vertex_index * 4 + 3] = 1.0
	var mesh_arrays := []
	mesh_arrays.resize(ArrayMesh.ARRAY_MAX)
	mesh_arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	mesh_arrays[ArrayMesh.ARRAY_NORMAL] = normals
	mesh_arrays[ArrayMesh.ARRAY_TANGENT] = tangents
	mesh_arrays[ArrayMesh.ARRAY_TEX_UV] = uvs
	mesh_arrays[ArrayMesh.ARRAY_INDEX] = indices
	var annulus_mesh := ArrayMesh.new()
	annulus_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	return annulus_mesh


# Shared subdivided [PlaneMesh] for [IVRings]. Kept at the default 2x2
# size (so the ring shaders' [code]length(UV * 2.0 - 1.0)[/code] radius math is unchanged) and
# subdivided so the per-vertex farwarp remap approximates the compression curve across the ring
# span. Instances set their own scale and rotation.
func _make_plane_mesh(subdivisions := 64) -> PlaneMesh:
	var plane_mesh := PlaneMesh.new()
	plane_mesh.subdivide_width = subdivisions
	plane_mesh.subdivide_depth = subdivisions
	return plane_mesh


func _make_circle_mesh(n_vertecies: int) -> ArrayMesh:
	# Unit circle. Stretch, rotate and shift into any orbit ellipse.
	var verteces := PackedVector3Array()
	verteces.resize(n_vertecies + 1)
	var angle_increment := TAU / n_vertecies
	var i := 0
	while i < n_vertecies:
		var angle: float = i * angle_increment
		verteces[i] = Vector3(cos(angle), sin(angle), 0.0) # radius = 1.0
		i += 1
	verteces[i] = verteces[0] # complete the loop
	var mesh_arrays := []
	mesh_arrays.resize(ArrayMesh.ARRAY_MAX)
	mesh_arrays[ArrayMesh.ARRAY_VERTEX] = verteces
	var circle_mesh := ArrayMesh.new()
	circle_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, mesh_arrays, [], {},
			ArrayMesh.ARRAY_FORMAT_VERTEX)
	return circle_mesh


func _make_open_conic_mesh(n_vertecies: int, e: float, max_r: float) -> ArrayMesh:
	# Unit (p = 1) parabola or hyperbola opening to the left (periapsis on +x
	# axis at longitude 0). For a rectangular hyperbola, use e = sqrt(2).
	# A Rectangular hyperbola can be stretched into any hyperbola.
	# Open conics are nearly a straight line at max_r. Using polar construction
	# concentrates vertexes where it is most curved. TODO: We need a few extra
	# vertexes on the looonnnng straight ends because long straight lines should
	# not be displayed as straight (due to perspective).
	# r = p/(1 + e * cos(nu))
	# cos(nu) = (p/r - 1)/e
	var verteces := PackedVector3Array()
	verteces.resize(n_vertecies)
	# Going clockwise starting from upper-left quadrant...
	var nu_start := acos((1.0 / max_r - 1.0) / e)
	var angle_increment := 2.0 * nu_start / (n_vertecies - 1)
	var i := 0
	while i < n_vertecies:
		var nu := nu_start - angle_increment * i # true anomaly
		var r := 1.0 / (1.0 + e * cos(nu))
		verteces[i] = Vector3(r * cos(nu), r * sin(nu), 0.0)
		i += 1
	#prints(verteces[0], verteces[1], verteces[-2], verteces[-1])
	var mesh_arrays := []
	mesh_arrays.resize(ArrayMesh.ARRAY_MAX)
	mesh_arrays[ArrayMesh.ARRAY_VERTEX] = verteces
	var open_conic_mesh := ArrayMesh.new()
	open_conic_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, mesh_arrays, [], {},
			ArrayMesh.ARRAY_FORMAT_VERTEX)
	return open_conic_mesh
