# body_orbit.gd
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
class_name IVBodyOrbit
extends MeshInstance3D

## Visual elliptic orbit of an [IVBody] instance.
##
## If FragmentIdentifier exists, then a shader
## is used to allow screen identification of the orbit loop.[br][br]
##
## TODO: Rename this class to IVOrbitEllipse. Modify code so that it sets
## visible = false for non-elliptic orbit (and doesn't break).[br][br]
##
## TODO: New class IVOrbitSegment. This class can draw a specified
## segment of an elliptic, parabolic or hyperbolic orbit (the latter two can
## only be segments). Lazy add only if a segment is asked for or if orbit ever
## goes parabolic or hyperbolic.[br][br]
##
## Both classes need to work without an IVBody dependence so we can construct
## visuals as needed, e.g., for a patched conic flight path. It should depend
## instead on IVOrbit (since that is a RefCounted that would also be used in
## a flight path).

const FRAGMENT_BODY_ORBIT := IVFragmentIdentifier.FRAGMENT_BODY_ORBIT

var _body: IVBody
var _color: Color
var _is_orbit_group_visible: bool
var _body_huds_visible: bool # too close / too far
var _body_visible: bool # this HUD node is sibling (not child) of its IVBody
var _dirty_transform := true

@onready var _fragment_identifier: IVFragmentIdentifier = IVGlobal.program.get(&"FragmentIdentifier")
@onready var _body_huds_state: IVBodyHUDsState = IVGlobal.program[&"BodyHUDsState"]


func _init(body: IVBody) -> void:
	_body = body
	name = "BodyOrbit" + body.name


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # FragmentIdentifier still processing
	_body.orbit_changed.connect(_set_ellipse_transform)
	_body_huds_state.visibility_changed.connect(_on_global_huds_changed)
	_body_huds_state.color_changed.connect(_set_color)
	_body.huds_visibility_changed.connect(_on_body_huds_changed)
	_body.visibility_changed.connect(_on_body_visibility_changed)
	mesh = IVGlobal.resources[&"circle_mesh"]
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	if _fragment_identifier: # use self-identifying fragment shader
		var data := _body.get_fragment_data(FRAGMENT_BODY_ORBIT)
		var fragment_id := _fragment_identifier.get_new_id_as_vec3(data)
		var shader_material := ShaderMaterial.new()
		shader_material.shader = IVGlobal.resources[&"orbit_id_shader"]
		shader_material.set_shader_parameter(&"fragment_id", fragment_id)
		material_override = shader_material
	else:
		var standard_material := StandardMaterial3D.new()
		standard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material_override = standard_material
	_set_color()
	_body_huds_visible = _body.huds_visible
	_body_visible = _body.visible
	_on_global_huds_changed()


func _on_global_huds_changed() -> void:
	_is_orbit_group_visible = _body_huds_state.is_orbit_visible(_body.flags)
	_set_visibility_state()


func _on_body_huds_changed(is_visible_: bool) -> void:
	_body_huds_visible = is_visible_
	_set_visibility_state()


func _on_body_visibility_changed() -> void:
	_body_visible = _body.visible
	_set_visibility_state()


func _set_visibility_state() -> void:
	visible = _is_orbit_group_visible and _body_huds_visible and _body_visible
	if visible and _dirty_transform:
		_set_ellipse_transform()


func _set_ellipse_transform(_is_intrinsic := false) -> void:
	if !visible:
		_dirty_transform = true
		return
	_dirty_transform = false
	transform = _body.get_orbit_ellipse_transform()


func _set_color() -> void:
	var color := _body_huds_state.get_orbit_color(_body.flags)
	if _color == color:
		return
	_color = color
	if _fragment_identifier:
		var shader_material: ShaderMaterial = material_override
		shader_material.set_shader_parameter(&"color", color)
	else:
		var standard_material: StandardMaterial3D = material_override
		standard_material.albedo_color = color
