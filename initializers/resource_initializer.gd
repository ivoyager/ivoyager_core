# shared_resource_initializer.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2025 Charlie Whitfield
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


var preloads: Dictionary[StringName, Resource] = {
	# shaders
	points_id_shader = preload("res://addons/ivoyager_core/shaders/points.id.gdshader"),
	points_l4l5_id_shader = preload("res://addons/ivoyager_core/shaders/points.l4l5.id.gdshader"),
	orbit_id_shader = preload("res://addons/ivoyager_core/shaders/orbit.id.gdshader"),
	orbits_id_shader = preload("res://addons/ivoyager_core/shaders/orbits.id.gdshader"),
	rings_shader = preload("res://addons/ivoyager_core/shaders/rings.gdshader"),
	rings_shadow_caster_shader = preload(
			"res://addons/ivoyager_core/shaders/rings_shadow_caster.gdshader"),
}

var constructors: Dictionary[StringName, Callable]= {
	&"sphere_mesh" : _make_sphere_mesh,
	&"circle_mesh" : _make_circle_mesh.bind(IVCoreSettings.vertecies_per_orbit),
	&"circle_mesh_low_res" : _make_circle_mesh.bind(IVCoreSettings.vertecies_per_orbit_low_res),
	&"parabola_mesh" : _make_open_conic_mesh.bind(IVCoreSettings.vertecies_per_orbit,
			1.0, IVCoreSettings.open_conic_max_radius),
	&"rectangular_hyperbola_mesh" : _make_open_conic_mesh.bind(IVCoreSettings.vertecies_per_orbit,
			sqrt(2.0), IVCoreSettings.open_conic_max_radius),
}

var _resources: Dictionary = IVGlobal.resources



func _init() -> void:
	_add_preloads()
	_make_shared_resources()
	IVGlobal.project_objects_instantiated.connect(_remove_self)



func _remove_self() -> void:
	IVGlobal.program.erase(&"ResourceInitializer")


func _add_preloads() -> void:
	for key in preloads:
		_resources[key] = preloads[key]


func _make_shared_resources() -> void:
	for key in constructors:
		var constructor := constructors[key]
		_resources[key] = constructor.call()


# constructor callables

func _make_sphere_mesh() -> SphereMesh:
	# Shared SphereMesh for stars, planets and moons. Scaled for oblateness.
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 2.0
	return sphere_mesh


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
