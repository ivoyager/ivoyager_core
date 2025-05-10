# math.gd
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
class_name IVMath
extends Object

## Math-related static functions.



static func get_x_rotation_matrix(th: float) -> Basis:
	return Basis(
		Vector3(1, 0, 0),
		Vector3(0, cos(th), -sin(th)),
		Vector3(0, sin(th), cos(th))
	)


static func get_y_rotation_matrix(th: float) -> Basis:
	return Basis(
		Vector3(cos(th), 0, sin(th)),
		Vector3(0, 1, 0),
		Vector3(-sin(th), 0, cos(th))
	)


static func get_z_rotation_matrix(th: float) -> Basis:
	return Basis(
		Vector3(cos(th), -sin(th), 0),
		Vector3(sin(th), cos(th), 0),
		Vector3(0, 0, 1)
	)


# Spherical
static func get_spherical2(position: Vector3) -> Vector2:
	var r := position.length()
	if r == 0.0:
		return Vector2.ZERO
	var right_ascension := fposmod(atan2(position.y, position.x), TAU) # 0,0 safe
	var declination := asin(position.z / r)
	return Vector2(right_ascension, declination)


static func convert_spherical2(right_ascension: float, declination: float) -> Vector3:
	# returns translation with r = 1.0
	var cos_dec := cos(declination)
	return Vector3(
		cos(right_ascension) * cos_dec,
		sin(right_ascension) * cos_dec,
		sin(declination)
	)


static func get_spherical3(position: Vector3) -> Vector3:
	var r := position.length()
	if r == 0.0:
		return Vector3.ZERO
	var right_ascension := fposmod(atan2(position.y, position.x), TAU)
	var declination := asin(position.z / r)
	return Vector3(right_ascension, declination, r)


static func convert_spherical3(spherical3: Vector3) -> Vector3:
	var right_ascension: float = spherical3[0]
	var declination: float = spherical3[1]
	var r: float = spherical3[2]
	var cos_decl := cos(declination)
	return Vector3(
		r * cos(right_ascension) * cos_decl,
		r * sin(right_ascension) * cos_decl,
		r * sin(declination)
	)


static func get_rotated_spherical3(position: Vector3, rotation := Basis.IDENTITY) -> Vector3:
	position = (position) * rotation
	return get_spherical3(position)


static func convert_rotated_spherical3(spherical3: Vector3, rotation := Basis.IDENTITY) -> Vector3:
	var position := convert_spherical3(spherical3)
	return rotation * (position)


static func get_latitude_longitude(position: Vector3) -> Vector2:
	# Convinience function; order & wrapping differ from spherical2 
	var spherical := get_spherical2(position)
	return Vector2(spherical[1], wrapf(spherical[0], -PI, PI))


static func get_fov_from_focal_length(focal_length: float) -> float:
	# This is for photography buffs who think in focal lengths (of full-frame
	# sensor) rather than fov. Godot sets fov to fit horizonal screen height by
	# default, so we use horizonal height of a full-frame sensor (11.67mm)
	# to calculate: fov = 2 * arctan(sensor_size / focal_length).
	const SENSOR_SIZE := 11.67
	return rad_to_deg(2.0 * atan(SENSOR_SIZE / focal_length))


static func get_focal_length_from_fov(fov: float) -> float:
	const SENSOR_SIZE := 11.67
	return SENSOR_SIZE / tan(deg_to_rad(fov) / 2.0)


static func get_fov_scaling_factor(fov: float) -> float:
	# This polynomial was empirically determined (with a tape measure) to
	# correct icon size on the screen for fov changes (more or less).
	return 0.00005 * fov * fov + 0.0001 * fov + 0.0816


# Quadratic fit and transformation

static func quadratic_fit(x_array: Array[float], y_array: Array[float]) -> Array[float]:
	# Returns [a, b, c] where y = ax^2 + bx + c is least-squares fit,
	# or [0.0, 0.0, 0.0] if indeterminant or nearly indeterminant.
	var n := x_array.size()
	assert(n == y_array.size())
	var sum_x := 0.0
	var sum_x2 := 0.0
	var sum_x3 := 0.0
	var sum_x4 := 0.0
	var sum_y := 0.0
	var sum_xy := 0.0
	var sum_x2y := 0.0
	for i in n:
		var x: float = x_array[i]
		var x2 := x * x
		var x3 := x2 * x
		var x4 := x3 * x
		var y: float = y_array[i]
		var xy := x * y
		var x2y := x2 * y
		sum_x += x
		sum_x2 += x2
		sum_x3 += x3
		sum_x4 += x4
		sum_y += y
		sum_xy += xy
		sum_x2y += x2y
	var mean_x := sum_x / n
	var mean_x2 := sum_x2 / n
	var mean_y := sum_y / n
	var S11 := sum_x2 - sum_x * mean_x
	var S12 := sum_x3 - sum_x * mean_x2
	var S22 := sum_x4 - sum_x2 * mean_x2
	var Sy1 := sum_xy - sum_y * mean_x
	var Sy2 := sum_x2y - sum_y * mean_x2
	var divisor := S22 * S11 - S12 * S12
	if is_zero_approx(divisor):
		return Array([0.0, 0.0, 0.0], TYPE_FLOAT, &"", null)
	var b := (Sy1 * S22 - Sy2 * S12) / divisor
	var a := (Sy2 * S11 - Sy1 * S12) / divisor
	var c := mean_y - b * mean_x - a * mean_x2
	return Array([a, b, c], TYPE_FLOAT, &"", null)


static func quadratic(x: float, coefficients: Array[float]) -> float:
	var a: float = coefficients[0]
	var b: float = coefficients[1]
	var c: float = coefficients[2]
	return a * x * x + b * x + c
