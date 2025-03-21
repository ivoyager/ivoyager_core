# dynamic_light.gd
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
class_name IVDynamicLight
extends DirectionalLight3D

## Hack system to generate proper light and shadows despite vast scale
## differences.
##
## This node self-adds DirectionalLight3D children that (together with itself)
## generate light and shadows on different mask levels.[br][br]
##
## 0b0001 (this node) - Astronomic objects
## 0b0010 (child1) - Astronomic objects
## 
## The parent node (this node) points in the direction from source to the
## camera. All lights are attenuated for source distance.


# from table
var dynamic_shadow_max: bool
var shadow_max_plus: float

var _world_targeting: Array = IVGlobal.world_targeting
var _parent_name: StringName

var _debug_frame := 0

## Names are constructed from the parent_name. E.g., STAR_SUN becomes
## STAR_SUN_0, STAR_SUN_1, STAR_SUN_2 for three lights imported from
## dynamic_lights.tsv.
func _init(parent_name: StringName) -> void:
	_parent_name = parent_name
	var this_light_name := StringName("DYNAMIC_LIGHT_" + parent_name + "_0")
	var row := IVTableData.get_row(this_light_name)
	assert(row != -1)
	IVTableData.db_build_object_all_fields(self, &"dynamic_lights", row)



func _ready() -> void:
	
	if !IVCoreSettings.apply_size_layers:
		return
	for i in IVCoreSettings.size_layers.size():
		var child_append := "_" + str(i + 1) # "_1", etc.
		var light_name := StringName("DYNAMIC_LIGHT_" + _parent_name + child_append)
		var row := IVTableData.get_row(light_name)
		assert(row != -1)
		var child_light := DirectionalLight3D.new()
		IVTableData.db_build_object_all_fields(child_light, &"dynamic_lights", row)
		add_child(child_light)
	
		prints(light_name, child_light.shadow_enabled, child_light.directional_shadow_blend_splits,
				child_light.directional_shadow_split_1)
	


func _process(_delta: float) -> void:
	# Camera position determines light direction and intensity.
	
	const BODYFLAGS_STAR_ORBITING := IVBody.BodyFlags.BODYFLAGS_STAR_ORBITING
	
	
	
	var camera: Camera3D = _world_targeting[2]
	if !camera:
		return
	var camera_global_position := camera.global_position
	var source_vector := camera_global_position - global_position
	var source_dist_sq := source_vector.length_squared()
	#var camera_parent_dist := camera.position.length()
	
	look_at(source_vector)
	
	if dynamic_shadow_max:
		# Shadows should be visible on the camera's parent and on the ancestor
		# "star orbiter". E.g., we see Io's shadow on Jupiter if we are anywhere
		# in Jupiter's system. Also, Jupiter should shade Io even if Io is on
		# the other side of Jupiter from us.
		# TODO: Optimize by having star_orbiter in IVGlobal container.
		var star_orbiter: IVBody = camera.get_parent_node_3d()
		while not star_orbiter.flags & BODYFLAGS_STAR_ORBITING:
			star_orbiter = star_orbiter.get_parent_node_3d() as IVBody
			if !star_orbiter:
				break
		if star_orbiter:
			var dist := (star_orbiter.global_position - camera_global_position).length()
			directional_shadow_max_distance = dist + shadow_max_plus
		
		
			_debug_frame += 1
			if _debug_frame % 60 == 0:
				prints(star_orbiter.name, dist, directional_shadow_max_distance)
		
		
		else: # camera is at a star or higher
			directional_shadow_max_distance = shadow_max_plus
	
	
