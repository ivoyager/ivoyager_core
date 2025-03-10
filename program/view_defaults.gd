# view_defaults.gd
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
class_name IVViewDefaults
extends RefCounted

## Generates default [IVView] instances that we might want to use.
##
## Moves the camera home at game start, unless move_home_at_start = false.
##
## TODO: Make these rows in table 'views.tsv'.


const CameraFlags := IVEnums.CameraFlags
const BodyFlags := IVEnums.BodyFlags
const AU := IVUnits.AU
const KM := IVUnits.KM
const METER := IVUnits.METER
const NULL_VECTOR3 := Vector3(-INF, -INF, -INF)

# project var
var move_home_at_start := true

# read-only!
var views := {}

var _view_script: Script


func _init() -> void:
	IVGlobal.project_objects_instantiated.connect(_on_project_objects_instantiated)
	IVGlobal.about_to_start_simulator.connect(_on_about_to_start_simulator)


# public API

func set_view(view_name: StringName, is_camera_instant_move := false) -> void:
	if !views.has(view_name):
		return
	var view: IVView = views[view_name]
	view.set_state(is_camera_instant_move)


func has_view(view_name: StringName) -> bool:
	return views.has(view_name)


# private

func _on_project_objects_instantiated() -> void:
	_view_script = IVGlobal.procedural_classes[&"View"]
	
	# visibilities & colors only
	_hide_all()
	_planets1()
	_asteroids1()
	_colors1()
	
	# camera (no selection)
	_zoom()
	_fortyfive()
	_top()
	
	# selection, camera, and more...
	_home()
	_cislunar()
	_system()
	_asteroids()


func _on_about_to_start_simulator(is_new_game: bool) -> void:
	if is_new_game and move_home_at_start:
		set_view(&"Home", true)


# visibilities & colors only

func _hide_all() -> void:
	# No HUDs visible.
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags = IVView.HUDS_VISIBILITY
	views.HideAll = view


func _planets1() -> void:
	# HUDs visible for the major bodies plus small moons (names and orbits).
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags = IVView.HUDS_VISIBILITY
	view.orbit_visible_flags = (
			# Must be from visibility_groups.tsv subset!
			BodyFlags.IS_TRUE_PLANET
			| BodyFlags.IS_DWARF_PLANET
			| BodyFlags.IS_PLANETARY_MASS_MOON
			| BodyFlags.IS_NON_PLANETARY_MASS_MOON
	)
	view.name_visible_flags = view.orbit_visible_flags | BodyFlags.IS_STAR
	views.Planets1 = view


func _asteroids1() -> void:
	# We set planet & moon visibilities for perspective. All asteroid points
	# are set but not asteroid orbits (which are overwhelming).
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags = IVView.HUDS_VISIBILITY
	view.orbit_visible_flags = (
			# Must be from visibility_groups.tsv subset!
			BodyFlags.IS_TRUE_PLANET
			| BodyFlags.IS_DWARF_PLANET
			| BodyFlags.IS_PLANETARY_MASS_MOON
			| BodyFlags.IS_NON_PLANETARY_MASS_MOON
			| BodyFlags.IS_ASTEROID
	)
	view.name_visible_flags = view.orbit_visible_flags | BodyFlags.IS_STAR
	
	# Set asteroid point visibilities from table.
	var visible_points_groups := view.visible_points_groups
	var SBG_CLASS_ASTEROIDS: int = IVEnums.SBGClass.SBG_CLASS_ASTEROIDS
	for row in IVTableData.get_n_rows(&"small_bodies_groups"):
		if IVTableData.get_db_bool(&"small_bodies_groups", &"skip", row):
			continue
		if IVTableData.get_db_int(&"small_bodies_groups", &"sbg_class", row) != SBG_CLASS_ASTEROIDS:
			continue
		var sbg_alias := IVTableData.get_db_string(&"small_bodies_groups", &"sbg_alias", row)
		visible_points_groups.append(sbg_alias)
	
	views.Asteroids1 = view


func _colors1() -> void:
	# Empty View dicts set default colors.
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags = IVView.HUDS_COLOR
	views.Colors1 = view


# camera (no selection)

func _zoom() -> void:
	# Camera positioned for best dramatic view. Orbit tracking. No selection.
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags = IVView.CAMERA_ORIENTATION | IVView.CAMERA_LONGITUDE
	view.camera_flags = CameraFlags.UP_LOCKED # | CameraFlags.TRACK_ORBIT
	# See IVCamera 'perspective distance'; METER below is really body radii
	view.view_position = Vector3(-INF, deg_to_rad(18.0), 3.0 * METER)
	view.view_rotations = Vector3.ZERO
	views[&"Zoom"] = view


func _fortyfive() -> void:
	# Camera positioned 45 degree above view. No selection or longitude.
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags = IVView.CAMERA_ORIENTATION
	view.camera_flags = CameraFlags.UP_LOCKED # | CameraFlags.TRACK_ORBIT
	# See IVCamera 'perspective distance'; METER below is really body radii
	view.view_position = Vector3(-INF, deg_to_rad(45.0), 10.0 * METER)
	view.view_rotations = Vector3.ZERO
	views[&"Fortyfive"] = view


func _top() -> void:
	# Camera positioned almost 90 degrees above. No selection or longitude.
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags = IVView.CAMERA_ORIENTATION
	view.camera_flags = CameraFlags.UP_LOCKED # | CameraFlags.TRACK_ORBIT
	# See IVCamera 'perspective distance'; METER below is really body radii
	view.view_position = Vector3(-INF, deg_to_rad(85.0), 25.0 * METER)
	view.view_rotations = Vector3.ZERO
	views[&"Top"] = view


# selection, camera, and more...

func _home() -> void:
	# Body, longitude & latitude from IVCoreSettings 'home_' settings. Ground tracking.
	# Planets, moons & spacecraft visible.
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags = (
			IVView.ALL_CAMERA
			| IVView.HUDS_VISIBILITY
			| IVView.IS_NOW
	)
	view.selection_name = IVCoreSettings.home_name
	view.camera_flags = (
			CameraFlags.UP_LOCKED
			| CameraFlags.TRACK_GROUND
	)
	# See IVCamera 'perspective distance'; METER below is really body radii
	view.view_position = Vector3(IVCoreSettings.home_longitude, IVCoreSettings.home_latitude, 3.0 * METER)
	view.view_rotations = Vector3.ZERO
	view.orbit_visible_flags = (
			# Must be from visibility_groups.tsv subset!
			BodyFlags.IS_TRUE_PLANET
			| BodyFlags.IS_DWARF_PLANET
			| BodyFlags.IS_PLANETARY_MASS_MOON
			| BodyFlags.IS_NON_PLANETARY_MASS_MOON
			| BodyFlags.IS_SPACECRAFT
	)
	view.name_visible_flags = view.orbit_visible_flags | BodyFlags.IS_STAR
	views[&"Home"] = view


func _cislunar() -> void:
	# Camera 15 degrees above Earth (ecliptic) at 120 Earth radii.
	# Planets, moons & spacecraft visible.
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags = IVView.ALL_CAMERA | IVView.HUDS_VISIBILITY
	view.selection_name = &"PLANET_EARTH"
	view.camera_flags = CameraFlags.UP_LOCKED | CameraFlags.TRACK_ORBIT
	# See IVCamera 'perspective distance'; METER below is really body radii
	view.view_position = Vector3(deg_to_rad(180.0), deg_to_rad(15.0), 120.0 * METER)
	view.view_rotations = Vector3.ZERO
	view.orbit_visible_flags = (
			# Must be from visibility_groups.tsv subset!
			BodyFlags.IS_TRUE_PLANET
			| BodyFlags.IS_DWARF_PLANET
			| BodyFlags.IS_PLANETARY_MASS_MOON
			| BodyFlags.IS_NON_PLANETARY_MASS_MOON
			| BodyFlags.IS_SPACECRAFT
	)
	view.name_visible_flags = view.orbit_visible_flags | BodyFlags.IS_STAR
	views[&"Cislunar"] = view


func _system() -> void:
	# Camera 15 degrees above the Sun at 70au.
	# Planets & moons visible.
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags = IVView.ALL_CAMERA | IVView.HUDS_VISIBILITY
	view.selection_name = &"STAR_SUN"
	view.camera_flags = CameraFlags.UP_LOCKED | CameraFlags.TRACK_ECLIPTIC
	view.view_position = Vector3(deg_to_rad(-90.0), deg_to_rad(15.0), 70.0 * AU)
	view.view_rotations = Vector3.ZERO
	view.orbit_visible_flags = (
			# Must be from visibility_groups.tsv subset!
			BodyFlags.IS_TRUE_PLANET
			| BodyFlags.IS_DWARF_PLANET
			| BodyFlags.IS_PLANETARY_MASS_MOON
			| BodyFlags.IS_NON_PLANETARY_MASS_MOON
	)
	view.name_visible_flags = view.orbit_visible_flags | BodyFlags.IS_STAR
	views[&"System"] = view


func _asteroids() -> void:
	# Camera 45 degree above the Sun at 15au for best view of Main Belt, Hildas
	# and Jupiter Trojans.
	# We set planet & moon visibilities for perspective. All asteroid points
	# are set but not asteroid orbits (which are overwhelming).
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	view.flags =  IVView.ALL_CAMERA | IVView.HUDS_VISIBILITY
	view.selection_name = &"STAR_SUN"
	view.camera_flags = CameraFlags.UP_LOCKED | CameraFlags.TRACK_ECLIPTIC
	view.view_position = Vector3(deg_to_rad(-90.0), deg_to_rad(45.0), 15.0 * AU)
	view.view_rotations = Vector3.ZERO

	view.orbit_visible_flags = (
			# Must be from visibility_groups.tsv subset!
			BodyFlags.IS_TRUE_PLANET
			| BodyFlags.IS_DWARF_PLANET
			| BodyFlags.IS_PLANETARY_MASS_MOON
			| BodyFlags.IS_NON_PLANETARY_MASS_MOON
			| BodyFlags.IS_ASTEROID
	)
	view.name_visible_flags = view.orbit_visible_flags | BodyFlags.IS_STAR
	
	# Set asteroid point visibilities from table.
	var visible_points_groups := view.visible_points_groups
	var SBG_CLASS_ASTEROIDS: int = IVEnums.SBGClass.SBG_CLASS_ASTEROIDS
	for row in IVTableData.get_n_rows(&"small_bodies_groups"):
		if IVTableData.get_db_bool(&"small_bodies_groups", &"skip", row):
			continue
		if IVTableData.get_db_int(&"small_bodies_groups", &"sbg_class", row) != SBG_CLASS_ASTEROIDS:
			continue
		var sbg_alias := IVTableData.get_db_string(&"small_bodies_groups", &"sbg_alias", row)
		visible_points_groups.append(sbg_alias)
	
	views[&"Asteroids"] = view
