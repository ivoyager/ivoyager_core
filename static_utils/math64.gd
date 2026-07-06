# math64.gd
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
class_name IVMath64
extends Object

## Double-precision ([PackedFloat64Array]) math for orbit-precision spatial data.
##
## Companion to [IVMath]. Under the ivoyager 64/32-bit idiom, real spatial quantities
## that need orbit precision are 64-bit [PackedFloat64Array], while [Vector3]/[Basis]
## outputs are 32-bit and flag their result as "for graphics use." This class owns the
## 64-bit representations and the rotation math that operates on them.[br][br]
##
## Layout conventions for the [PackedFloat64Array] arguments here:[br]
## [code]translation[/code] / [code]position[/code] / [code]velocity[/code]: size 3, [code][x, y, z][/code].[br]
## [code]state[/code]: size 6, [code][x, y, z, vx, vy, vz][/code].[br]
## [code]basis[/code]: size 9, the three axis vectors (columns) concatenated
## [code][x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z][/code], where x / y / z are
## [member Basis.x] / [member Basis.y] / [member Basis.z]. [method to_basis] / [method from_basis]
## round-trip through this order.[br][br]
##
## A size-9 basis multiplies a size-3 vector exactly as the equivalent [Basis] would (columns
## are the axes): [code]result = v.x * col0 + v.y * col1 + v.z * col2[/code] (see [method rotate]).


## Returns the [Basis] equivalent of a size-9 column-major [param basis] (see class
## description). [code]to_basis(b) * v[/code] equals [method rotate] with the same
## inputs, cast to 32-bit. Inverse of [method from_basis].
static func to_basis(basis: PackedFloat64Array) -> Basis:
	# basis holds the three columns (axis vectors); Basis(x, y, z) sets those same columns.
	return Basis(
		Vector3(basis[0], basis[1], basis[2]),
		Vector3(basis[3], basis[4], basis[5]),
		Vector3(basis[6], basis[7], basis[8])
	)


## Returns the size-9 column-major [PackedFloat64Array] for [param basis] (see class
## description). Inverse of [method to_basis].
static func from_basis(basis: Basis) -> PackedFloat64Array:
	return PackedFloat64Array([
		basis.x.x, basis.x.y, basis.x.z,
		basis.y.x, basis.y.y, basis.y.z,
		basis.z.x, basis.z.y, basis.z.z,
	])


## Writes [code]basis * (x, y, z)[/code] into [param out] at [param offset], [param offset]+1,
## [param offset]+2. No allocation; [param out] must already be sized. This is the primitive
## used by orbit-precision getters to rotate into a shared buffer.
static func rotate_into(basis: PackedFloat64Array, x: float, y: float, z: float,
		out: PackedFloat64Array, offset := 0) -> void:
	# basis * (x, y, z) = x·col0 + y·col1 + z·col2 (columns are the axes).
	out[offset] = x * basis[0] + y * basis[3] + z * basis[6]
	out[offset + 1] = x * basis[1] + y * basis[4] + z * basis[7]
	out[offset + 2] = x * basis[2] + y * basis[5] + z * basis[8]


## Returns [code]basis * (x, y, z)[/code] as a new size-3 [PackedFloat64Array]. Allocating
## convenience wrapper for [method rotate_into].
static func rotate(basis: PackedFloat64Array, x: float, y: float, z: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(3)
	rotate_into(basis, x, y, z, out, 0)
	return out


## Returns size-3 [param a] - [param b] element-wise as a new [PackedFloat64Array].
static func subtract(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


## Returns the Euclidean distance between size-3 translations [param a] and [param b].
static func distance(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var dx := a[0] - b[0]
	var dy := a[1] - b[1]
	var dz := a[2] - b[2]
	return sqrt(dx * dx + dy * dy + dz * dz)
