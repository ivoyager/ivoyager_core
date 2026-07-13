# astronomy.gd
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
extends Node

## Singleton [IVAstronomy] provides astronomy constants, properites, and methods.
##
## This class is an autoload so that it (and its constants) can be replaced,
## e.g., for a fictional universe with a different gravitational constant. For
## autoload replacement, see
## res://addons/ivoyager_core/ivoyager_override_template.cfg.[br][br]
##
## Internal epoch time is always J2000.0 (noon on Jan 1, 2000). Data table
## values specified otherwise are converted.[br][br]
##
## In this simulator, always assume that the coordinate system is ecliptic
## unless something indicates otherwise E.g., [IVOrbit] has an [member
## IVOrbit.reference_basis] (which is in reference to ecliptic). In ecliptic
## space, the z-axis points to ecliptic north and the x-axis points to vernal
## equinox. Commentary: In contrast, real astronomers never tell you the
## coordinate system. You're just supposed to know that RA/dec specifies Earth
## equatorial coordinates, moon orbits are "local planet equatorial" or
## "Laplace" (unless it is THE Moon, of course), etc...[br][br]
##
## See also [IVOrbit] for orbital mechanics (including static methods).[br][br]
##
## TODO: Define "epoch" and "julian_period" here for applications that span
## 10000s of years or more. It should be possible to reset the whole sim to a
## new epoch (on signal) after some very long interval. The problem is that
## [param time] in seconds loses precision at large absolute values. [IVBody]
## orbit and rotation look ok out to a million years due to use of GDScript
## "float" (64-bit precision) but asteroid points start jump-skipping at around
## 10000 AD due to 32-bit shader math. 


# Dev note: Don't add non-Godot class dependencies in this file! These are
# avoided here to prevent circular reference issues.


## Newton's gravitational constant in simulator units.
const G := 6.67430e-11 * IVUnits.METER ** 3 / (IVUnits.KG * IVUnits.SECOND ** 2)
## Julian Day Number for the J2000.0 epoch (noon on Jan 1, 2000).
const EPOCH_JULIAN_DAY := 2451545.0 # J2000; noon on Jan 1, 2000
## Unit vector pointing to ecliptic north in ecliptic coordinates.
const ECLIPTIC_NORTH := Vector3(0, 0, 1)
## Unit vector pointing to the vernal equinox in ecliptic (and equatorial)
## coordinates; corresponds to ecliptic longitude 0.
const VERNAL_EQUINOX := Vector3(1, 0, 0)
## Earth's axial tilt at J2000.0 (radians).
const OBLIQUITY_OF_THE_ECLIPTIC := deg_to_rad(23.4392911) # at J2000
## Unit vector pointing to the north celestial pole (ICRF z-axis) in ecliptic
## coordinates.
const CELESTIAL_NORTH := Vector3(0, sin(OBLIQUITY_OF_THE_ECLIPTIC),
		cos(OBLIQUITY_OF_THE_ECLIPTIC))
## Basis that rotates an ecliptic-frame vector into the equatorial frame.
const ECLIPTIC_TO_EQUATORIAL_ROTATION := Basis(
		Vector3(1, 0, 0),
		Vector3(0, cos(OBLIQUITY_OF_THE_ECLIPTIC), sin(OBLIQUITY_OF_THE_ECLIPTIC)),
		Vector3(0, -sin(OBLIQUITY_OF_THE_ECLIPTIC), cos(OBLIQUITY_OF_THE_ECLIPTIC))
	)
## Inverse of [constant ECLIPTIC_TO_EQUATORIAL_ROTATION]; rotates equatorial to
## ecliptic.
const EQUATORIAL_TO_ECLIPTIC_ROTATION := Basis(
		Vector3(1, 0, 0),
		Vector3(0, cos(OBLIQUITY_OF_THE_ECLIPTIC), -sin(OBLIQUITY_OF_THE_ECLIPTIC)),
		Vector3(0, sin(OBLIQUITY_OF_THE_ECLIPTIC), cos(OBLIQUITY_OF_THE_ECLIPTIC))
	)



## Returns a unit vector in ecliptic Cartesian coordinates for given angles in
## equatorial coordinates.
func get_ecliptic_unit_vector_from_equatorial_angles(right_ascension: float,
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
func get_equatorial_coordinates_from_ecliptic_vector(vector3: Vector3) -> Vector3:
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
func get_basis_from_z_axis_and_vernal_equinox(z_axis: Vector3) -> Basis:
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
func get_ecliptic_basis_from_equatorial_north(right_ascension: float, declination: float
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


## Returns a basis in ecliptic coordinates that has z-axis in the specified
## direction and x-axis at the ascending node of the basis xy-plane on the
## ICRF (Earth) equatorial plane. This is the reference basis convention for
## JPL planetary satellite mean elements
## ([url]https://ssd.jpl.nasa.gov/sats/elem/[/url]), where the longitude of the
## ascending node is "measured from the node of the reference plane on the
## ICRF equator". [param z_axis] must be a unit vector in ecliptic coordinates.
## Note: If the specified z_axis is exactly in the direction of celestial north
## (or south), it will be rotated 0.0001 radians around the ecliptic y-axis
## (this is necessary in order to have a determined x-axis).
func get_basis_from_z_axis_and_icrf_equator_node(z_axis: Vector3) -> Basis:
	assert(z_axis.is_normalized())
	const SINGULARITY_BUMP := 0.0001
	const ECLIPTIC_Y := Vector3(0, 1, 0)
	if z_axis.is_equal_approx(CELESTIAL_NORTH) or z_axis.is_equal_approx(-CELESTIAL_NORTH):
		z_axis = z_axis.rotated(ECLIPTIC_Y, -SINGULARITY_BUMP)
	var x := CELESTIAL_NORTH.cross(z_axis).normalized() # ascending node on ICRF equator
	var y := z_axis.cross(x)
	return Basis(x, y, z_axis)


# *****************************************************************************
# Sun occlusion (eclipse/shadow) math. Each method has a GLSL twin in
# shaders/_sun_occlusion.gdshaderinc; keep the math in exact sync.


## Returns the visible fraction of the sun's disc given an occluding disc:
## exact two-circle (lens) overlap in the planar small-angle approximation,
## with exact containment tests, so totality, annularity and partial phases
## all behave. All args in radians. GLSL twin:
## [code]sun_occlusion_disc_fraction()[/code].
func get_two_disc_visible_fraction(sun_angular_radius: float,
		occluder_angular_radius: float, separation: float) -> float:
	var a := maxf(sun_angular_radius, 1e-7)
	var b := occluder_angular_radius
	var c := separation
	if c >= a + b:
		return 1.0 # no overlap
	if c <= b - a:
		return 0.0 # total: occluder covers the sun disc
	if c <= a - b:
		return 1.0 - (b * b) / (a * a) # annular/transit: occluder inside the sun disc
	if b > 20.0 * a:
		# A much larger occluder disc (e.g. a planet seen from a nearby craft or
		# its rings): its edge is locally straight across the small sun disc, and
		# the exact lens formula below cancels catastrophically (an a^2-scale
		# result from b^2-scale terms). Use the stable straight-edge chord
		# fraction instead.
		var x := clampf((c - b) / a, -1.0, 1.0) # sun-center distance past the edge, in sun radii
		return 0.5 + (x * sqrt(1.0 - x * x) + asin(x)) / PI
	var a2 := a * a
	var b2 := b * b
	var c2 := c * c
	var lens := (a2 * acos(clampf((c2 + a2 - b2) / (2.0 * c * a), -1.0, 1.0))
			+ b2 * acos(clampf((c2 + b2 - a2) / (2.0 * c * b), -1.0, 1.0))
			- 0.5 * sqrt(maxf((a + b - c) * (c + a - b) * (c - a + b) * (c + a + b), 0.0)))
	return 1.0 - lens / (PI * a2)


## Returns the visible fraction of the sun's disc from [param position] past
## one oblate-spheroid occluder. [param sun_direction] and [param occluder_pole]
## are unit vectors; either pole sign works. All positions and lengths must
## share one frame and unit. GLSL twin:
## [code]sun_occlusion_spheroid_fraction()[/code].
func get_spheroid_occlusion_fraction(position: Vector3, sun_direction: Vector3,
		sun_angular_radius: float, occluder_center: Vector3, occluder_pole: Vector3,
		equatorial_radius: float, polar_radius: float) -> float:
	var offset := occluder_center - position
	# Stretch space along the pole so the spheroid becomes a sphere of the
	# equatorial radius; the same affine map applies to the sun ray.
	var stretch := equatorial_radius / polar_radius - 1.0
	var offset_stretched := offset + stretch * offset.dot(occluder_pole) * occluder_pole
	var sun_direction_stretched := (sun_direction
			+ stretch * sun_direction.dot(occluder_pole) * occluder_pole).normalized()
	var dist := offset_stretched.length()
	if dist <= equatorial_radius:
		return 1.0 # at/inside the occluder
	var to_occluder := offset_stretched / dist
	if to_occluder.dot(sun_direction_stretched) <= 0.0:
		return 1.0 # occluder is not sunward of the position
	var occluder_angular_radius := asin(clampf(equatorial_radius / dist, 0.0, 1.0))
	var separation := acos(clampf(to_occluder.dot(sun_direction_stretched), -1.0, 1.0))
	return get_two_disc_visible_fraction(sun_angular_radius, occluder_angular_radius,
			separation)


## Returns the transmission of direct sunlight through an annular ring layer,
## modeled as a 1D radial opacity profile ([param profile_image], width x 1,
## FORMAT_R8, spanning radius [param texture_inner] to [param texture_outer] -
## the padded texture range, not the physical ring edges). Includes the
## slanted-path optical depth; averages the profile over the physical penumbra
## footprint (this bounded box average is the CPU stand-in for the GLSL twin's
## mip sampling). All positions and lengths share one frame and unit;
## [param sun_direction] and [param ring_normal] are unit vectors, either
## normal sign works. GLSL twin: [code]sun_occlusion_ring_transmission()[/code].
func get_ring_transmission(profile_image: Image, position: Vector3,
		sun_direction: Vector3, sun_angular_radius: float, ring_center: Vector3,
		ring_normal: Vector3, texture_inner: float, texture_outer: float) -> float:
	var cos_slant := ring_normal.dot(sun_direction)
	var abs_cos := maxf(absf(cos_slant), 1e-4)
	var signed_cos := abs_cos if cos_slant >= 0.0 else -abs_cos
	var ray_length := ring_normal.dot(ring_center - position) / signed_cos
	if ray_length <= 0.0:
		return 1.0 # ring plane not sunward
	var plane_hit := position + sun_direction * ray_length - ring_center
	var texture_u := (plane_hit.length() - texture_inner) / (texture_outer - texture_inner)
	if texture_u <= 0.0 or texture_u >= 1.0:
		return 1.0 # outside the profile range
	var width := profile_image.get_width()
	var texel_size := (texture_outer - texture_inner) / width
	var penumbra_texels := 2.0 * sun_angular_radius * ray_length / texel_size
	var center_texel := texture_u * width
	var samples := clampi(int(penumbra_texels) + 1, 1, 9)
	var alpha_sum := 0.0
	for i in samples:
		var sample_texel := center_texel + ((i + 0.5) / samples - 0.5) * penumbra_texels
		var x := clampi(int(sample_texel), 0, width - 1)
		alpha_sum += profile_image.get_pixel(x, 0).r
	var alpha := alpha_sum / samples
	return pow(1.0 - alpha, 1.0 / abs_cos)
