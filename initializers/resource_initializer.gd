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
## Resources are added to IVGlobal.resources. These resources are constructed
## or loaded by Callables or paths set here, and do not depend on the
## presence of ivoyager_assets (see IVAssetsInitializer for that).


var paths: Dictionary[StringName, String] = {
	# shaders
	points_id_shader = "res://addons/ivoyager_core/shaders/points.id.gdshader",
	points_l4l5_id_shader = "res://addons/ivoyager_core/shaders/points.l4l5.id.gdshader",
	orbit_id_shader = "res://addons/ivoyager_core/shaders/orbit.id.gdshader",
	orbits_id_shader = "res://addons/ivoyager_core/shaders/orbits.id.gdshader",
	rings_shader = "res://addons/ivoyager_core/shaders/rings.gdshader",
}

var constructors: Dictionary[StringName, Callable]= {
	&"sphere_mesh" : _make_sphere_mesh,
	&"circle_mesh" : _make_circle_mesh.bind(IVCoreSettings.vertecies_per_orbit),
	&"circle_mesh_low_res" : _make_circle_mesh.bind(IVCoreSettings.vertecies_per_orbit_low_res),
}

var _resources: Dictionary = IVGlobal.resources


func _init() -> void:
	_load_resource_paths()
	_make_shared_resources()
	IVGlobal.initializers_inited.connect(_remove_self)


func _remove_self() -> void:
	IVGlobal.program.erase(&"ResourceInitializer")


func _load_resource_paths() -> void:
	for key in paths:
		var path := paths[key]
		var resource: Resource = load(path)
		assert(resource, "Failed to load resource at " + path)
		_resources[key] = resource


func _make_shared_resources() -> void:
	for key in constructors:
		var constructor := constructors[key]
		_resources[key] = constructor.call()


# constructor callables

func _make_sphere_mesh() -> SphereMesh:
	# Shared SphereMesh for stars, planets and moons. Model scale is used to
	# create oblateness.
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 2.0
	return sphere_mesh


func _make_circle_mesh(n_vertecies: int) -> ArrayMesh:
	# All orbits (e < 1.0) use shared circle mesh with basis scaling to create
	# the orbital ellipse.
	var verteces := PackedVector3Array()
	verteces.resize(n_vertecies + 1)
	var angle_increment := TAU / n_vertecies
	var i := 0
	while i < n_vertecies:
		var angle: float = i * angle_increment
		verteces[i] = Vector3(sin(angle), cos(angle), 0.0) # radius = 1.0
		i += 1
	verteces[i] = verteces[0] # complete the loop
	var mesh_arrays := []
	mesh_arrays.resize(ArrayMesh.ARRAY_MAX)
	mesh_arrays[ArrayMesh.ARRAY_VERTEX] = verteces
	var circle_mesh := ArrayMesh.new()
	circle_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, mesh_arrays, [], {},
			ArrayMesh.ARRAY_FORMAT_VERTEX)
	return circle_mesh
