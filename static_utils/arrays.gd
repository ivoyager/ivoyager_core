# arrays.gd
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
class_name IVArrays
extends Object

## Array static utility methods.


## Init array of given [param size], [param fill], and type parameters. Keep
## [param fill] == null to not fill.
static func init_array(size: int, fill: Variant = null, type := -1, class_name_ := &"",
		script: Variant = null) -> Array:
	var array: Array
	if type == -1:
		array = []
	else:
		array = Array([], type, class_name_, script)
	array.resize(size)
	if fill == null:
		return array
	array.fill(fill)
	return array


## Duplicates [param a] and adds elements of [param b] not already present.
## The resulting array will have the same type as [param a]; it's an error if
## [param b] has elements inconsistent with this type.
static func get_union(a: Array, b: Array) -> Array:
	var union := a.duplicate()
	for element: Variant in b:
		if not union.has(element):
			union.append(element)
	return union


## Duplicates [param a] and removes any elements that are not also present in
## [param b]. The resulting array will have the same type as [param a].
static func get_intersection(a: Array, b: Array) -> Array:
	var intersection := a.duplicate()
	var i := a.size()
	while i > 0:
		i -= 1
		if not b.has(a[i]):
			intersection.remove_at(i)
	return intersection


## Merges the contents of [param from] Array into the provided [param into]
## Array [b]without[/b] duplication.
static func merge_array(into: Array, from: Array) -> void:
	for item: Variant in from:
		if not into.has(item):
			into.append(item)


## Returns the sum of all elements of [param array].
static func get_float_sum(array: Array[float]) -> float:
	var sum := 0.0
	for i in array.size():
		sum += array[i]
	return sum


## Returns the arithmetic mean of [param array]. Errors on an empty array.
static func get_float_average(array: Array[float]) -> float:
	var size := array.size()
	var sum := 0.0
	for i in size:
		sum += array[i]
	return sum / size


## Returns a new array of fractions (summing to 1.0) computed by dividing each
## element of [param proportions] by the total. The input is not modified;
## see [method set_fractions_from_proportions] for the in-place version.
static func get_fractions_from_proportions(proportions: Array[float]) -> Array[float]:
	var size := proportions.size()
	var sum := 0.0
	for i in size:
		sum += proportions[i]
	var fractions: Array[float] = []
	fractions.resize(size)
	for i in size:
		fractions[i] = proportions[i] / sum
	return fractions


## In-place variant of [method get_fractions_from_proportions]; rescales
## [param array] so its elements sum to 1.0.
static func set_fractions_from_proportions(array: Array[float]) -> void:
	var size := array.size()
	var sum := 0.0
	for i in size:
		sum += array[i]
	for i in size:
		array[i] = array[i] / sum
