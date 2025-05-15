# astronomy.gd
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
extends Node

## Added as singleton "IVAstronomy".
##
## This singleton has astronomy specific constants, static variables, and
## static functions. It's an autoload so that it can be replaced, e.g., for
## a fictional universe with a different gravitational constant (see
## ivoyager_core/override_template.cfg).[br][br]
##
## Epoch time is J2000.0 (noon on Jan 1, 2000). Data table values specified
## otherwise are converted.[br][br]
##
## In this simulator, always assume that the coordinate system is ecliptic
## unless indicated otherwise. In ecliptic space, the z-axis points to ecliptic
## north and the x-axis points to vernal equinox.[br][br]
##
## WARNING/Commentary: Astronomers never tell you what coordinate system they
## are working in! For example, right accension / declination specification is
## always (I think) in equatorial coordinates, while most other things are
## ecliptic. Except moon orbits, of course. Unless it is The Moon...[br][br]
##
## See also static methods in [IVOrbit].[br][br]
##
## TODO: For games or sims spanning 10000s of years or more, the sim will need
## a reset to a new "epoch" time. The problem is that [param time] in seconds
## will lose precision if it gets too large. (Fortunatly, Godot uses double
## precision for float, so we're good for quite a range...) Probably we need a
## static var here "epoch_offset_j2000". To update to J10000, all "..._at_epoch"
## and "..._time" members in all objects would need recalculation.

const G := 6.67430e-11 * IVUnits.METER ** 3 / (IVUnits.KG * IVUnits.SECOND ** 2)
const EPOCH_JULIAN_DAY := 2451545.0 # J2000; noon on Jan 1, 2000
const ECLIPTIC_NORTH := Vector3(0, 0, 1)
const VERNAL_EQUINOX := Vector3(1, 0, 0)
const OBLIQUITY_OF_THE_ECLIPTIC := deg_to_rad(23.4392911) # at J2000
const ECLIPTIC_TO_EQUATORIAL_ROTATION := Basis(
		Vector3(1, 0, 0),
		Vector3(0, cos(OBLIQUITY_OF_THE_ECLIPTIC), sin(OBLIQUITY_OF_THE_ECLIPTIC)),
		Vector3(0, -sin(OBLIQUITY_OF_THE_ECLIPTIC), cos(OBLIQUITY_OF_THE_ECLIPTIC))
	)
const EQUATORIAL_TO_ECLIPTIC_ROTATION := Basis(
		Vector3(1, 0, 0),
		Vector3(0, cos(OBLIQUITY_OF_THE_ECLIPTIC), -sin(OBLIQUITY_OF_THE_ECLIPTIC)),
		Vector3(0, sin(OBLIQUITY_OF_THE_ECLIPTIC), cos(OBLIQUITY_OF_THE_ECLIPTIC))
	)



## Returns a unit vector in ecliptic Cartesian coordinates for given angles in
## equatorial coordinates.
static func get_ecliptic_unit_vector_from_equatorial_angles(right_ascension: float,
		declination: float) -> Vector3:
	const COS_OBL := cos(OBLIQUITY_OF_THE_ECLIPTIC)
	const SIN_OBL := sin(OBLIQUITY_OF_THE_ECLIPTIC)
	var cos_dec := cos(declination)
	var xeq := cos_dec * cos(right_ascension)
	var yeq := cos_dec * sin(right_ascension)
	var zeq := sin(declination)
	return Vector3(xeq, yeq * COS_OBL + zeq * SIN_OBL, -yeq * SIN_OBL + zeq * COS_OBL)


## Returns Vector3(right_ascension, declination, radius) in equatorial coordinates
## for [param vector3] (of any length) in ecliptic Cartesian coordinates.
static func get_equatorial_coordinates_from_ecliptic_vector(vector3: Vector3) -> Vector3:
	var r := vector3.length()
	if r == 0.0:
		return Vector3.ZERO
	vector3 = ECLIPTIC_TO_EQUATORIAL_ROTATION * vector3
	var right_ascension := fposmod(atan2(vector3.y, vector3.x), TAU) # 0,0 safe
	var declination := asin(vector3.z / r)
	return Vector3(right_ascension, declination, r)



## Returns a basis that has z-axis in the specified direction and x-axis
## in the plane of z-axis and vernal equinox. I.e., the x-axis will be at
## longitude 0. Works in ecliptic or equatorial coordinates, where the resuting
## basis will be in the same coordinate system as [param z_axis] (which must be
## a unit vector). Note: If the specified z_axis is exacly in the direction of
## vernal equinox, it will be rotated 0.0001 radians around the y-axis
## (this is necessary in order to have a determined x-axis).
static func get_basis_from_z_axis_and_vernal_equinox(z_axis: Vector3) -> Basis:
	assert(z_axis.is_normalized())
	const SINGULARITY_BUMP := 0.0001
	const ECLIPTIC_Y := Vector3(0, 1, 0)
	if z_axis.is_equal_approx(VERNAL_EQUINOX): # edge case (tested at <~0.00001 rotated in 32-bit)
		z_axis = z_axis.rotated(ECLIPTIC_Y, -SINGULARITY_BUMP) 
	var y := z_axis.cross(VERNAL_EQUINOX).normalized() # perpendicular to vernal equinox
	var x := y.cross(z_axis) # in the plane of vernal equinox (usually close to it)
	return Basis(x, y, z_axis)


## Returns a basis in ecliptic space that has z-axis in the north direction
## (specified in equatorial angles) and x-axis in the plane of north
## and vernal equinox. I.e., the x-axis will be at ecliptic longitude 0.
## Note: If the specified north is exacly in the direction of vernal equinox,
## it will be bumped 0.0001 radians in the direction of ecliptic north (this
## is necessary in order to have a determined x-axis).
static func get_ecliptic_basis_from_equatorial_north(right_ascension: float, declination: float
		) -> Basis:
	const SINGULARITY_BUMP := 0.0001
	const ECLIPTIC_Y := Vector3(0, 1, 0)
	const COS_OBL := cos(OBLIQUITY_OF_THE_ECLIPTIC)
	const SIN_OBL := sin(OBLIQUITY_OF_THE_ECLIPTIC)
	var cos_dec := cos(declination)
	var xeq := cos_dec * cos(right_ascension)
	var yeq := cos_dec * sin(right_ascension)
	var zeq := sin(declination)
	var z := Vector3(xeq, yeq * COS_OBL + zeq * SIN_OBL, -yeq * SIN_OBL + zeq * COS_OBL) # north
	if z.is_equal_approx(VERNAL_EQUINOX): # edge case (tested at <~0.00001 rotated in 32-bit)
		z = z.rotated(ECLIPTIC_Y, -SINGULARITY_BUMP) 
	var y := z.cross(VERNAL_EQUINOX).normalized() # perpendicular to vernal equinox
	var x := y.cross(z) # in the plane of vernal equinox (usually close to it)
	return Basis(x, y, z)
